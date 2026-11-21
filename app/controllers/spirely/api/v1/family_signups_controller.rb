module Spirely
  module Api
    module V1
      # The "confirm your email" link Create Account sends (5ST-85). No
      # sign-in: the token in the link is the key. Opening it confirms the
      # email (FamilySignup#confirm!) and says what's next: set up the
      # account (invited, with invite_path), sign in (has_account), or the
      # new-family form (started).
      class FamilySignupsController < BaseController
        skip_before_action :authenticate!
        before_action { require_feature!("family_signup") }
        before_action :set_signup

        # GET /api/v1/family_signups/:token
        def show
          @signup.confirm!
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
          invitation = @signup.invitation if @signup.status == "invited"
          { status: @signup.status, phone: @signup.phone, email: @signup.email,
            church_name: Current.church.name, expired: @signup.expired?,
            invite_path: invitation && "/invite/#{invitation.token}" }
        end
      end
    end
  end
end
