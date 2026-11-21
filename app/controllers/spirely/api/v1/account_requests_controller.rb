module Spirely
  module Api
    module V1
      # Create Account on the church's site (5ST-85). No sign-in. Answers the
      # same whether or not we found them (Spirely::AccountRequest says what
      # gets sent), so it can't be used to learn who's in the church's
      # records. Rate-limited by phone and email (rack-attack, in the app).
      class AccountRequestsController < BaseController
        skip_before_action :authenticate!
        before_action { require_feature!("family_signup") }

        # POST /api/v1/account_requests  { phone, email }
        def create
          Spirely::AccountRequest.call(church: Current.church, phone: params[:phone], email: params[:email])
          render json: { message: "Check your email for the next step." }, status: :accepted
        rescue ActiveRecord::RecordInvalid => e
          render json: { error: e.record.errors.full_messages.to_sentence, code: "validation_error" },
                 status: :unprocessable_entity
        end
      end
    end
  end
end
