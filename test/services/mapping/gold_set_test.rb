require "test_helper"

module Mapping
  class GoldSetTest < ActiveSupport::TestCase
    test "loads the default gold set with mapped and no_target entries" do
      gold = GoldSet.new

      assert gold.mapped.any?, "expected mapped entries"
      assert gold.no_target.any?, "expected no_target entries"
    end

    test "mapped entries carry a source object and at least one acceptable target" do
      GoldSet.new.mapped.each do |e|
        assert e.source_object.present?, "mapped entry missing source_object"
        assert e.targets.any?, "#{e.source_object} has no targets"
      end
    end

    test "no_target entries have no targets (gap-discovery)" do
      GoldSet.new.no_target.each { |e| assert_empty e.targets }
    end

    test "source_objects unions mapped and no_target" do
      gold = GoldSet.new
      assert_includes gold.source_objects, "Brand__c"
      assert_includes gold.source_objects, "sfsrm__Payment__c"
    end

    test "field_pairs split source object/field and carry acceptable targets" do
      pairs = GoldSet.new.field_pairs
      assert pairs.any?, "expected field-level pairs"
      q = pairs.find { |p| p.source_field == "sfsrm__Quantity__c" }
      assert_equal "sfsrm__Line_Item__c", q.source_object
      assert_includes q.targets, "InvoiceLineItem.quantity"
    end
  end
end
