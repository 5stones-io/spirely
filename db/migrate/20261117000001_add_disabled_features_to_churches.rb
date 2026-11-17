# Core feature switches (5ST-81): the core features a church has turned
# off (Church::FEATURES keys). Stores what's off rather than what's on, so
# every church keeps everything it has today and a feature added later
# starts on.
class AddDisabledFeaturesToChurches < ActiveRecord::Migration[7.2]
  def change
    add_column :churches, :disabled_features, :string, array: true, default: [], null: false
  end
end
