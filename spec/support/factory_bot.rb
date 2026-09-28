# FactoryBot configuration (LLD §12).
#
# `factory_bot_rails` loads `spec/factories.rb` itself. This file only loads the
# one constant the factories need while building —
# `spec/support/reference_data.rb` — and points at where sequences are rewound
# (the `before` hook in spec/rails_helper.rb and features/support/hooks.rb).
require_relative "reference_data"
