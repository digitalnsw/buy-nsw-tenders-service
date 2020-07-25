$:.push File.expand_path("lib", __dir__)

# Maintain your gem's version:
require "tender_service/version"

# Describe your gem and declare its dependencies:
Gem::Specification.new do |spec|
  spec.name        = "tender_service"
  spec.version     = TenderService::VERSION
  spec.authors     = ["Arman"]
  spec.email       = ["arman.zrb@gmail.com"]
  spec.homepage    = ""
  spec.summary     = "Summary of TenderService."
  spec.description = "Description of TenderService."
  spec.license     = "MIT"

  spec.files = Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
end
