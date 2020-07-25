module TenderService
  class Engine < ::Rails::Engine
    isolate_namespace TenderService
    config.generators.api_only = true
  end
end
