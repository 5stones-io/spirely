module Spirely
  module Api
    module V1
      module Admin
        # Confirms a church's saved Twilio credentials can actually deliver
        # a text to a real phone, before InviteSender is allowed to use
        # them for a real invite — see ChurchIntegration#twilio_verified?
        # for why twilio_configured? (credential presence) alone isn't
        # trustworthy (a real send silently went nowhere due to A2P 10DLC
        # carrier filtering, confirmed 2026-08-09).
        #
        # Deliberately stateless — no new columns/table for the pending
        # code itself, just an encrypted token (Spirely::Encryption,
        # the same primitive already used for every credential column on
        # this model) round-tripped through the client, same shape as the
        # PCO connect flow's signed short-lived token. Encrypted, not just
        # signed, so the code itself can't be read back out of the token
        # client-side — the whole point is that only actually receiving
        # the real text should reveal it.
        class TwilioVerificationController < BaseController
          before_action :require_admin!

          CODE_EXPIRY = 10.minutes

          # POST /api/v1/admin/twilio_verification { phone: }
          def create
            integration = Current.church.church_integration
            unless integration&.twilio_configured?
              render json: { error: "Save your Twilio credentials first.", code: "not_configured" },
                     status: :unprocessable_entity
              return
            end

            phone = params[:phone].to_s.strip
            if phone.blank?
              render json: { error: "Enter a phone number to send the test code to.", code: "validation_error" },
                     status: :unprocessable_entity
              return
            end

            code = format("%06d", SecureRandom.random_number(1_000_000))
            Spirely::Sms.new(integration).send(
              to: phone, body: "Your Spirely verification code is #{code}. It expires in 10 minutes."
            )

            payload = { "church_id" => Current.church.id, "code" => code, "expires_at" => CODE_EXPIRY.from_now.to_i }
            token = Spirely::Encryption.encrypt(payload.to_json)
            render json: { token: token }
          rescue Spirely::SmsError => e
            render json: { error: "Twilio couldn't send the test code: #{e.message}", code: "sms_error" },
                   status: :bad_gateway
          end

          # POST /api/v1/admin/twilio_verification/confirm { token:, code: }
          def confirm
            payload = decode_token(params[:token])
            unless payload && payload["church_id"] == Current.church.id
              render json: { error: "Verification session expired — send a new code.", code: "invalid_token" },
                     status: :unprocessable_entity
              return
            end

            if payload["expires_at"].to_i < Time.current.to_i
              render json: { error: "That code has expired — send a new one.", code: "expired" },
                     status: :unprocessable_entity
              return
            end

            unless ActiveSupport::SecurityUtils.secure_compare(payload["code"].to_s, params[:code].to_s.strip)
              render json: { error: "That code doesn't match.", code: "invalid_code" }, status: :unprocessable_entity
              return
            end

            integration = Current.church.church_integration
            integration.update!(twilio_verified_at: Time.current)
            render json: { twilio_verified: true }
          end

          private

          def decode_token(token)
            return nil if token.blank?
            JSON.parse(Spirely::Encryption.decrypt(token))
          rescue JSON::ParserError, TypeError, ArgumentError
            nil
          end
        end
      end
    end
  end
end
