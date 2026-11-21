module Spirely
  module Api
    module V1
      # The new-family form a Create Account link opens (5ST-85). No
      # sign-in: the token in the link is the key.
      class FamilySignupsController < BaseController
        skip_before_action :authenticate!
        before_action { require_feature!("family_signup") }
        before_action :set_signup

        # GET /api/v1/family_signups/:token
        def show
          render json: signup_json
        end

        # PATCH /api/v1/family_signups/:token
        #   { first_name, last_name, address, children: [{ first_name, last_name, birthdate, allergies }] }
        def update
          unless @signup.status == "started"
            return render json: { error: "We already have your family's details.", code: "already_sent" },
                          status: :unprocessable_entity
          end
          if @signup.expired?
            return render json: { error: "This link has expired. Ask for a new one on Create Account.", code: "expired" },
                          status: :unprocessable_entity
          end

          @signup.submit!(params.permit(:first_name, :last_name, :address,
                                        children: %i[first_name last_name birthdate allergies]))
          Spirely::FamilySignupNotifier.submitted(@signup)
          render json: signup_json
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.to_sentence, code: "validation_error" },
                 status: :unprocessable_entity
        end

        private

        def set_signup
          @signup = Current.church.family_signups.find_by!(token: params[:token])
        end

        def signup_json
          { status: @signup.status, phone: @signup.phone, email: @signup.email,
            church_name: Current.church.name, expired: @signup.expired? }
        end
      end
    end
  end
end
