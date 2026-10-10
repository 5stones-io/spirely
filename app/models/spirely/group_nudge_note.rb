module Spirely
  # One entry in a follow-up's history — a note someone wrote, the outcome
  # that closed it, or Spirely's own "created" line (no author account).
  class GroupNudgeNote < ApplicationRecord
    belongs_to :church
    belongs_to :group_nudge, class_name: "Spirely::GroupNudge"
    belongs_to :author_account, class_name: "::Account", optional: true
  end
end
