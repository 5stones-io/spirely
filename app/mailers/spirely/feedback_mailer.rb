module Spirely
  class FeedbackMailer < ApplicationMailer
    # "New feedback from Megan Torres: Event reflection" — to each admin
    # and owner (FeedbackNotifier), linking to it in the staff inbox.
    def submitted(feedback, to)
      @feedback = feedback
      @church   = feedback.church
      @url      = Spirely::FeedbackNotifier.inbox_url(feedback)
      mail(to: to, subject: "New feedback from #{feedback.sender_name}: #{feedback.category_label}")
    end
  end
end
