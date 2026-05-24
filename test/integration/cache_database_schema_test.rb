require "test_helper"

# Production cache_store is :solid_cache_store backed by the `cache` database.
# If db/cache_structure.sql lacks solid_cache_entries (the table SolidCache
# reads/writes against), a fresh production deploy crashes on the first
# Rails.cache.write — and Salesforce::TokenCache lives on Rails.cache, so the
# very first JWT exchange would die. This test exists to keep that schema
# present.
class CacheDatabaseSchemaTest < ActiveSupport::TestCase
  # Tiny abstract AR class scoped to the cache database, just for schema
  # introspection in tests. Not exported because the app uses SolidCache::Record
  # internally and shouldn't depend on this.
  class CacheConnection < ActiveRecord::Base
    self.abstract_class = true
    connects_to database: { writing: :cache }
  end

  test "cache database has the solid_cache_entries table" do
    tables = CacheConnection.connection.tables
    assert_includes tables, "solid_cache_entries",
                    "expected the cache database to have solid_cache_entries; without it, " \
                    "a fresh production deploy crashes on the first Rails.cache.write " \
                    "and Salesforce::TokenCache.fetch fails on the first JWT exchange"
  end

  test "solid_cache_entries has the indices SolidCache reads from" do
    indices = CacheConnection.connection.indexes("solid_cache_entries").map(&:name)
    assert_includes indices, "index_solid_cache_entries_on_key_hash",
                    "the key_hash unique index is SolidCache's primary read path"
    assert_includes indices, "index_solid_cache_entries_on_byte_size",
                    "byte_size index supports SolidCache's max_size eviction"
  end
end
