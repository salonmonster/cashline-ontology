require "test_helper"

module Mapping
  class DossierTest < ActiveSupport::TestCase
    setup do
      @run = ExtractionRun.create!(api_version: "62.0", include_sensitive: false)
      @sobject = Sobject.create!(extraction_run: @run, api_name: "sfsrm__Transaction__c", label: "Transaction")
      @snapshot = CashlineSnapshot.create!(loaded_at: Time.current, sha256: "s", schema_json: {
        "classes" => [
          {
            "class_name" => "Invoice", "namespace" => nil, "table_name" => "invoices",
            "columns" => [
              { "name" => "balance_due_cents", "type" => "integer", "null" => false, "comment" => nil },
              { "name" => "customer_account_id", "type" => "integer", "null" => false, "comment" => "FK" },
              { "name" => "status", "type" => "integer", "enum_values" => { "draft" => 0, "paid" => 1 } }
            ],
            "associations" => [
              { "name" => "customer_account", "macro" => "belongs_to", "class_name" => "Customer::Account", "foreign_key" => "customer_account_id" },
              { "name" => "line_items", "macro" => "has_many", "class_name" => "InvoiceLineItem", "foreign_key" => "invoice_id" }
            ]
          }
        ]
      })
      @dossier = Dossier.new(snapshot: @snapshot)
    end

    def profile_for(sfield, **attrs)
      op = ObjectProfile.create!(extraction_run: @run, sobject: @sobject, record_count: 100, status: "complete")
      FieldProfile.create!({ object_profile: op, sfield: sfield, null_rate: 0.0, distinct_count: 2 }.merge(attrs))
    end

    test "source dossier of a safe picklist field carries object role, picklist, help, and value distribution" do
      sf = Sfield.create!(sobject: @sobject, api_name: "CurrencyIsoCode", label: "Currency ISO Code",
        data_type: "picklist", nillable: false, sensitivity: "safe",
        raw_describe: { "inlineHelpText" => "ISO code", "referenceTo" => [] })
      sf.spicklist_values.create!(value: "USD", active: true)
      sf.spicklist_values.create!(value: "CAD", active: true)
      profile_for(sf, top_values: [ { "value" => "USD", "count" => 90 }, { "value" => "CAD", "count" => 10 } ])

      d = @dossier.source(sf)
      assert_equal "sailfin", d[:side]
      assert_equal "Transaction", d[:object][:label]
      assert_equal %w[USD CAD], d[:picklist]
      assert_equal "ISO code", d[:field][:help]
      assert d[:profile][:top_values].present?, "a safe field should expose its value distribution"

      text = @dossier.render(d)
      assert_includes text, "picklist: USD, CAD"
      assert_includes text, "top=[USD(90)"
    end

    test "source dossier exposes a reference field's target object" do
      sf = Sfield.create!(sobject: @sobject, api_name: "AccountId", data_type: "reference",
        sensitivity: "safe", raw_describe: { "referenceTo" => [ "Account" ], "relationshipName" => "Account" })
      assert_equal [ "Account" ], @dossier.source(sf)[:references]
    end

    test "sensitivity gate: a financial field is structural-metadata-only" do
      sf = Sfield.create!(sobject: @sobject, api_name: "sfsrm__Amount__c", label: "SECRET_LABEL",
        data_type: "currency", sensitivity: "financial", calculated_formula: "Base + Tax",
        raw_describe: { "inlineHelpText" => "SECRET_HELP" })
      sf.spicklist_values.create!(value: "SECRET_VALUE", active: true)
      profile_for(sf, distinct_count: 500,
        top_values: [ { "value" => "12345", "count" => 3 } ], min_value: 1, max_value: 99999)

      d = @dossier.source(sf)
      # structural stats survive
      assert_equal 500, d[:profile][:distinct]
      assert_equal "currency", d[:field][:type]
      # field content + value-derived stats are withheld
      assert_nil d[:field][:label]
      assert_nil d[:field][:help]
      assert_nil d[:field][:formula]
      assert_nil d[:picklist]
      assert_nil d[:profile][:top_values]
      assert_nil d[:profile][:numeric_range]

      text = @dossier.render(d)
      refute_includes text, "SECRET_LABEL"
      refute_includes text, "SECRET_HELP"
      refute_includes text, "SECRET_VALUE"
      refute_includes text, "Base + Tax"
    end

    test "target dossier surfaces enum values, FK target, and parent relations" do
      status = @dossier.target("Invoice", "status")
      assert_equal %w[draft paid], status[:enum_values]
      assert_includes status[:relations], "Customer::Account"

      fk = @dossier.target("Invoice", "customer_account_id")
      assert_equal "Customer::Account", fk[:belongs_to][:class_name]
    end

    test "target returns nil for a field the snapshot does not have" do
      assert_nil @dossier.target("Invoice", "nonexistent")
    end

    test "target raises without a snapshot" do
      assert_raises(ArgumentError) { Dossier.new.target("Invoice", "status") }
    end
  end
end
