require "rails_helper"

# Staff posts that tag children (5ST-78): only the tagged children's
# families see them.
RSpec.describe Spirely::FamilyPost, "tagged posts", type: :model do
  let(:church) { create(:church, enabled_modules: ["kidsmin"]) }
  let(:staff)  { create(:membership, :admin, church: church) }
  let(:emma_family) { create(:spirely_family, church: church) }
  let(:noah_family) { create(:spirely_family, church: church) }
  let(:emma) { create(:spirely_child, family: emma_family, first_name: "Emma") }
  let(:noah) { create(:spirely_child, family: noah_family, first_name: "Noah") }

  def photo = Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files/store-item.png"), "image/png")

  def post_to(children, photos: nil, body: "Psalm 23 crafts today!")
    described_class.post_to_families!(church: church, author: staff, body: body, child_ids: children.map(&:id), photos: photos)
  end

  it "is approved straight away, for the tagged families only, with no posting family" do
    post = post_to([emma, noah])

    expect(post).to have_attributes(status: "approved", audience: "tagged", family: nil, author: staff, post_type: "other")
    expect(post.tagged_children).to contain_exactly(emma, noah)
    expect(post).to be_staff_post
  end

  it "needs at least one child, all from this church" do
    expect { post_to([]) }.to raise_error(Spirely::FamilyPost::TagError, "Tag at least one child.")
    elsewhere = create(:spirely_child, family: create(:spirely_family))
    expect { post_to([emma, elsewhere]) }.to raise_error(Spirely::FamilyPost::TagError, "Some of those children aren't at this church.")
    expect(described_class.count).to eq(0)
  end

  it "won't put photos on a post that tags a child whose family asked for none" do
    emma.update!(no_photos: true)

    expect { post_to([emma, noah], photos: [photo]) }
      .to raise_error(Spirely::FamilyPost::TagError, "Emma's family asked for no photos. Remove the photos or untag Emma to post.")
    expect(described_class.count).to eq(0)

    expect(post_to([emma, noah]).tagged_children).to include(emma)
  end

  describe ".visible_to_family" do
    it "includes a tagged post only for the families of children it tags" do
      post = post_to([emma])

      expect(church.family_posts.visible_to_family(emma_family)).to include(post)
      expect(church.family_posts.visible_to_family(noah_family)).not_to include(post)
    end
  end

  describe "#remove_tags!" do
    it "takes this family's children off the post, leaving everyone else's" do
      post = post_to([emma, noah])

      post.remove_tags!(emma_family)

      expect(post.reload.tagged_children).to contain_exactly(noah)
      expect(church.family_posts.visible_to_family(emma_family)).not_to include(post)
      expect(church.family_posts.visible_to_family(noah_family)).to include(post)
    end
  end

  it "lets go of a child who's removed" do
    post = post_to([emma, noah])
    # The database removes the tag (a Child's own destroy needs host-app
    # models the gem alone doesn't have).
    emma.delete
    expect(post.reload.tagged_children).to contain_exactly(noah)
  end
end
