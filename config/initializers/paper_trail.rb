# PaperTrail configuration — LLD §7.4
#
# `SalaryRecord` is the only versioned model (LLD §7). It records who changed a
# salary, what changed, and whether the change came from the UI or a bulk import
# (LLD §7.2).

# Store versions as JSON rather than YAML.
#
# The YAML serializer deserializes through Psych.safe_load with Rails' permitted
# class list, which on Rails 8.1 is [Symbol] only. Every money column is a
# BigDecimal and the schema also has Date and TimeWithZone, so deserializing a
# version raises Psych::DisallowedClass — which PaperTrail rescues into an empty
# hash, making `version.changeset` silently return {} and breaking the "what
# changed / previous / new" requirement in LLD §7.1.
#
# This requires `versions.object` and `versions.object_changes` to be jsonb.
PaperTrail.serializer = PaperTrail::Serializers::JSON

# Keep the last N versions per record. The retention policy that LLD §7.4 left
# open is resolved here: 50 versions is deep enough to answer an audit question
# about any single salary without unbounded growth on a table that only grows.
PaperTrail.config.version_limit = 50

# :legacy raises on create but only *logs* a failure to version an update or a
# delete, so a salary change could be written without its audit trail while the
# caller sees success. :exception raises in every case instead. Valid values are
# :legacy, :log, :exception and :silent — anything else falls through and
# swallows version errors.
PaperTrail.config.version_error_behavior = :exception
