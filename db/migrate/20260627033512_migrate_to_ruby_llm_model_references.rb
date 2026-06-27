class MigrateToRubyLlmModelReferences < ActiveRecord::Migration[8.0]
  def up
    say_with_time "Loading RubyLLM models into the registry" do
      Model.save_to_database
      Model.count
    end
  end

  def down
    Model.delete_all if table_exists?(:models)
  end
end
