class AddLogoShapeToChurches < ActiveRecord::Migration[7.2]
  def change
    # Chad's ask 2026-08-28, after uploading a real wide/landscape logo
    # (a wordmark + mascot, not square) and finding the app-shell brand
    # mark's fixed-square, object-cover treatment would crop it badly.
    # "circle" matches the pre-existing visual treatment (now literally
    # rounded-full, see BrandMark.tsx) so every already-uploaded logo
    # keeps working without a forced re-pick; "square"/"rectangle" are
    # new, opt-in.
    add_column :churches, :logo_shape, :string, default: "circle", null: false
  end
end
