require "./spec_helper"

describe CombinePDF::Options do
  describe "#initialize" do
    it "uses sensible defaults for the booklet use case" do
      opts = CombinePDF::Options.new
      opts.font_size.should eq(10.0)
      opts.color.should eq({0.2, 0.2, 0.2})
      opts.margin.should eq(24.0)
      opts.global_format.should eq("%page%/%total%")
      opts.partition_format.should eq("%page%/%total%")
      opts.hide_partition_when_single.should be_true
      opts.skip_pages.should be_empty
    end

    it "accepts user overrides" do
      opts = CombinePDF::Options.new(
        font_size: 14.0,
        color: {0.8, 0.0, 0.0},
        margin: 36.0,
        global_format: "Page %page% of %total%",
        partition_format: "(%page% / %total%)",
        hide_partition_when_single: false,
        skip_pages: [1, 2],
      )
      opts.font_size.should eq(14.0)
      opts.color.should eq({0.8, 0.0, 0.0})
      opts.margin.should eq(36.0)
      opts.global_format.should eq("Page %page% of %total%")
      opts.partition_format.should eq("(%page% / %total%)")
      opts.hide_partition_when_single.should be_false
      opts.skip_pages.should eq([1, 2])
    end
  end
end
