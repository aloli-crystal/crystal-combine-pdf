require "./spec_helper"
require "yaml"

# Le `Producer` du PDF généré contient `crystal-combine-pdf #{VERSION}`.
# Avant la v1.0.31.34, la constante `VERSION` était hardcodée dans
# `version.cr` et pouvait diverger du `version:` de `shard.yml`. Toutes
# les releases de v1.0.31.27 à v1.0.31.33 ont écrit « 1.0.31.26 » dans
# le `/Producer` à cause de cette désynchronisation.
#
# Depuis v1.0.31.34, la constante est lue au compile-time via le macro
# `read_file` directement depuis `shard.yml`. Ce spec garantit que cette
# garantie tient et qu'on ne régressera pas.
describe "CombinePDF::VERSION" do
  it "matche la version du shard.yml (compile-time, pas de désynchro possible)" do
    shard_yml_path = File.join(__DIR__, "..", "shard.yml")
    File.exists?(shard_yml_path).should be_true
    yml = YAML.parse(File.read(shard_yml_path))
    yml_version = yml["version"].as_s
    CombinePDF::VERSION.should eq(yml_version)
  end

  it "est non vide et au format X.Y.Z[.N]" do
    CombinePDF::VERSION.should match(/^\d+\.\d+\.\d+(\.\d+)?$/)
  end
end
