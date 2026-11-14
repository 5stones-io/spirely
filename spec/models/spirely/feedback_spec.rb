require "rails_helper"

# Feedback and requests (5ST-80).
RSpec.describe Spirely::Feedback, type: :model do
  let(:church)  { create(:church) }
  let(:account) { create(:account) }

  def upload(name, type = "application/octet-stream")
    Rack::Test::UploadedFile.new(Rails.root.join("spec/fixtures/files", name), type, original_filename: name)
  end

  def build_feedback(**attrs)
    described_class.new({ church: church, account: account, category: "general", body: "Thanks!", sender_role: "member" }.merge(attrs))
  end

  it "starts out new" do
    feedback = build_feedback
    feedback.save!
    expect(feedback.status).to eq("new")
  end

  it "needs a known category and a message" do
    expect(build_feedback(category: "complaint")).not_to be_valid
    expect(build_feedback(body: " ")).not_to be_valid
  end

  it "keeps how it went only for event reflections" do
    reflection = build_feedback(category: "reflection", tone: "went_well")
    reflection.save!
    expect(reflection.tone).to eq("went_well")

    noticed = build_feedback(category: "noticed", tone: "went_well")
    noticed.save!
    expect(noticed.tone).to be_nil

    expect(build_feedback(category: "reflection", tone: "great")).not_to be_valid
  end

  describe "#attach_files" do
    let(:feedback) { build_feedback.tap(&:save!) }

    it "takes pictures and documents, typed from their contents, under the church's own prefix" do
      feedback.attach_files([upload("store-item.png"), upload("supply-list.pdf"), upload("sign-ups.xlsx")])

      types = feedback.ordered_attachments.map { |a| a.blob.content_type }
      expect(types).to eq(%w[image/png application/pdf application/vnd.openxmlformats-officedocument.spreadsheetml.sheet])
      expect(feedback.attachments.map { |a| a.blob.key }).to all(start_with("church-#{church.id}/feedback/"))
    end

    it "won't take a file whose contents don't match its name" do
      expect { feedback.attach_files([upload("not-a.pdf", "application/pdf")]) }
        .to raise_error(Spirely::Feedback::AttachmentError, "Attachments have to be pictures, PDF, Word, PowerPoint or Excel files.")
      expect(feedback.attachments).to be_empty
    end

    it "takes up to 5 files of 10 MB each, and checks them all before saving any" do
      expect { feedback.attach_files(Array.new(6) { upload("store-item.png") }) }
        .to raise_error(Spirely::Feedback::AttachmentError, "You can attach up to 5 files.")

      big = upload("supply-list.pdf")
      allow(big).to receive(:size).and_return(11.megabytes)
      expect { feedback.attach_files([upload("store-item.png"), big]) }
        .to raise_error(Spirely::Feedback::AttachmentError, "Each file has to be under 10 MB.")
      expect(feedback.attachments.reload).to be_empty
    end
  end

  it "goes when its church does, and lets go of a task that's deleted" do
    task = create(:spirely_task, church: church)
    feedback = build_feedback(task: task).tap(&:save!)

    task.destroy!
    expect(feedback.reload.task).to be_nil

    # The gem alone can't destroy a Church (some of its associations are
    # host-app models), so check the association that will.
    expect(Church.reflect_on_association(:feedbacks).options[:dependent]).to eq(:destroy)
  end
end
