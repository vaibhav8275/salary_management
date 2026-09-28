class CurrencyBlueprint < Blueprinter::Base
  identifier :id

  fields :code, :name, :symbol
end
