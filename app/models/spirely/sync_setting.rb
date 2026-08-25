module Spirely
  class SyncSetting < ApplicationRecord
    CONFLICT_STRATEGIES = %w[pco_wins local_wins newest_wins].freeze

    belongs_to :church

    validates :conflict_resolution, inclusion: { in: CONFLICT_STRATEGIES }
    validates :sync_frequency_hours, numericality: { greater_than: 0, only_integer: true }

    def effective_ministry_tag
      pco_ministry_tag.presence
    end
  end
end
