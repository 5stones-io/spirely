require "openssl"
require "base64"

module Spirely
  module Encryption
    ALGORITHM = "aes-256-gcm"
    IV_LENGTH = 12
    TAG_LENGTH = 16

    def self.encrypt(plaintext)
      return nil if plaintext.nil?

      key    = key_bytes
      iv     = OpenSSL::Random.random_bytes(IV_LENGTH)
      cipher = OpenSSL::Cipher.new(ALGORITHM)
      cipher.encrypt
      cipher.key = key
      cipher.iv  = iv

      ciphertext = cipher.update(plaintext) + cipher.final
      tag        = cipher.auth_tag(TAG_LENGTH)

      Base64.strict_encode64(iv + tag + ciphertext)
    end

    def self.decrypt(encoded)
      return nil if encoded.nil?

      raw        = Base64.strict_decode64(encoded)
      iv         = raw[0, IV_LENGTH]
      tag        = raw[IV_LENGTH, TAG_LENGTH]
      ciphertext = raw[(IV_LENGTH + TAG_LENGTH)..]

      cipher = OpenSSL::Cipher.new(ALGORITHM)
      cipher.decrypt
      cipher.key      = key_bytes
      cipher.iv       = iv
      cipher.auth_tag = tag

      cipher.update(ciphertext) + cipher.final
    rescue OpenSSL::Cipher::CipherError
      nil
    end

    def self.key_bytes
      key = Spirely.configuration.encryption_key
      raise "Spirely.configuration.encryption_key is not set" if key.blank?
      [key].pack("H*")
    end
    private_class_method :key_bytes
  end
end
