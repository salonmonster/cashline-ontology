class CreateExtractionRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :extraction_runs do |t|
      t.references :user, null: true, foreign_key: true
      t.string :status, null: false, default: "queued"
      t.string :api_version, null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.boolean :include_sensitive, null: false, default: false
      t.datetime :retained_until
      t.jsonb :seed_objects, null: false, default: []
      t.jsonb :walk_options, null: false, default: {}
      t.jsonb :limits_at_start
      t.jsonb :limits_at_end
      t.jsonb :installed_packages
      t.jsonb :partial_failures, null: false, default: []
      t.text :error_message
      t.text :content_hash
      t.string :directory_token, null: false
      t.timestamps
    end

    add_index :extraction_runs, :status
    add_index :extraction_runs, :include_sensitive
    add_index :extraction_runs, :started_at
    add_index :extraction_runs, :directory_token, unique: true
  end
end
