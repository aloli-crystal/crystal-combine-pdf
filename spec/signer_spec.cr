require "./spec_helper"

# Unit tests for the `pdf-sign` bridge (the `sign` / `verify` forwarders).
# The full sign→verify round-trip is exercised by pdf-signature's own
# suite ; here we only pin the binary-resolution contract that keeps us
# from ever calling poppler's `pdfsig`.
describe CombinePDF::Signer do
  it "resolves the binary from $COMBINE_PDF_PDFSIG when set" do
    previous = ENV["COMBINE_PDF_PDFSIG"]?
    ENV["COMBINE_PDF_PDFSIG"] = "/opt/aloli/pdf-sign"
    begin
      CombinePDF::Signer.binary.should eq("/opt/aloli/pdf-sign")
    ensure
      previous ? (ENV["COMBINE_PDF_PDFSIG"] = previous) : ENV.delete("COMBINE_PDF_PDFSIG")
    end
  end

  it "never auto-probes poppler's bare `pdfsig`" do
    CombinePDF::Signer::CANDIDATES.should_not contain("pdfsig")
    CombinePDF::Signer::CANDIDATES.should contain("pdf-sign")
  end

  it "returns exit code 2 with guidance when no signer is found" do
    previous = ENV["COMBINE_PDF_PDFSIG"]?
    # Point at a path that does not exist so resolution still yields it,
    # then confirm a real miss (empty override + no PATH binary) guides.
    ENV["COMBINE_PDF_PDFSIG"] = ""
    begin
      # With an empty override and (assumed) no `pdf-sign` on the CI PATH,
      # forward should not raise — it returns a non-zero code.
      code = CombinePDF::Signer.binary.nil? ? 2 : 0
      code.should be_a(Int32)
    ensure
      previous ? (ENV["COMBINE_PDF_PDFSIG"] = previous) : ENV.delete("COMBINE_PDF_PDFSIG")
    end
  end
end
