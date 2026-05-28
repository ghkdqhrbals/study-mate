#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "fileutils"
require "json"
require "net/http"
require "openssl"
require "time"
require "uri"

BUNDLE_IDENTIFIER = "io.github.ghkdqhrbals.StudyMate"
PROFILE_TYPE = "MAC_APP_DIRECT"

def require_env(name)
  value = ENV[name]
  abort "Missing required environment variable: #{name}" if value.nil? || value.empty?
  value
end

def base64url(value)
  Base64.urlsafe_encode64(value).delete("=")
end

def es256_jwt(key_id:, issuer_id:, private_key_path:)
  private_key = OpenSSL::PKey.read(File.read(private_key_path))
  now = Time.now.to_i
  header = { alg: "ES256", kid: key_id, typ: "JWT" }
  payload = { iss: issuer_id, iat: now, exp: now + 20 * 60, aud: "appstoreconnect-v1" }
  signing_input = "#{base64url(header.to_json)}.#{base64url(payload.to_json)}"
  der_signature = private_key.dsa_sign_asn1(OpenSSL::Digest::SHA256.digest(signing_input))
  sequence = OpenSSL::ASN1.decode(der_signature)
  raw_signature = sequence.value.map { |integer| integer.value.to_s(2).rjust(32, "\0") }.join
  "#{signing_input}.#{base64url(raw_signature)}"
end

def api_request(method, path, token, query: nil, body: nil)
  uri = URI::HTTPS.build(host: "api.appstoreconnect.apple.com", path: path, query: query && URI.encode_www_form(query))
  request_class = method == :get ? Net::HTTP::Get : Net::HTTP::Post
  request = request_class.new(uri)
  request["Authorization"] = "Bearer #{token}"
  request["Content-Type"] = "application/json"
  request.body = JSON.generate(body) if body

  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
  parsed = JSON.parse(response.body)
  return parsed if response.is_a?(Net::HTTPSuccess)

  warn JSON.pretty_generate(parsed)
  abort "App Store Connect API request failed: #{method.to_s.upcase} #{uri} returned #{response.code}"
end

def normalized_serial(value)
  value.to_s.delete(":").upcase
end

key_id = require_env("APPSTORE_CONNECT_KEY_ID")
issuer_id = require_env("APPSTORE_CONNECT_ISSUER_ID")
private_key_path = require_env("APPSTORE_CONNECT_PRIVATE_KEY_PATH")
certificate_serial = normalized_serial(require_env("DEVELOPER_ID_CERTIFICATE_SERIAL"))
profile_output_path = require_env("PROFILE_OUTPUT_PATH")
token = es256_jwt(key_id: key_id, issuer_id: issuer_id, private_key_path: private_key_path)

bundle_response = api_request(
  :get,
  "/v1/bundleIds",
  token,
  query: {
    "filter[identifier]" => BUNDLE_IDENTIFIER,
    "filter[platform]" => "MAC_OS",
    "limit" => "1"
  }
)
bundle_id = bundle_response.fetch("data").first&.fetch("id")
abort "Bundle ID not found in App Store Connect: #{BUNDLE_IDENTIFIER}" unless bundle_id

certificate_types = %w[DEVELOPER_ID_APPLICATION]
certificates = certificate_types.flat_map do |certificate_type|
  api_request(
    :get,
    "/v1/certificates",
    token,
    query: {
      "filter[certificateType]" => certificate_type,
      "limit" => "200"
    }
  ).fetch("data")
end

certificate = certificates.find do |item|
  attributes = item.fetch("attributes")
  attributes["activated"] != false && normalized_serial(attributes["serialNumber"]) == certificate_serial
end

unless certificate
  abort "No App Store Connect Developer ID Application certificate matches installed certificate serial #{certificate_serial}."
end

profile_name = "StudyMate GitHub Actions #{Time.now.utc.strftime("%Y%m%d%H%M%S")}"
profile_response = api_request(
  :post,
  "/v1/profiles",
  token,
  body: {
    data: {
      type: "profiles",
      attributes: {
        name: profile_name,
        profileType: PROFILE_TYPE
      },
      relationships: {
        bundleId: {
          data: { type: "bundleIds", id: bundle_id }
        },
        certificates: {
          data: [{ type: "certificates", id: certificate.fetch("id") }]
        }
      }
    }
  }
)

profile = profile_response.fetch("data")
content = profile.fetch("attributes").fetch("profileContent")
FileUtils.mkdir_p(File.dirname(profile_output_path))
File.binwrite(profile_output_path, Base64.decode64(content))

puts "Created Developer ID provisioning profile: #{profile.fetch("attributes").fetch("name")} (#{profile.fetch("attributes").fetch("uuid")})"
