namespace :runs do
  desc "Rebuild the relational tables for a given run directory token. Usage: rake runs:rebuild_db RUN=<directory_token>"
  task rebuild_db: :environment do
    token = ENV["RUN"] or abort("Pass RUN=<directory_token> (see ExtractionRun#directory_token)")
    run = ExtractionRun.find_by!(directory_token: token)
    puts "Rebuilding relational data for run #{run.id} (#{token})..."
    Runs::RelationalLoader.load!(run)
    puts "Loaded #{run.sobjects.count} objects, #{Sfield.joins(:sobject).where(sobjects: { extraction_run_id: run.id }).count} fields."
  end
end
