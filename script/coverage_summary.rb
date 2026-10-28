# Markdown summary of the last spec run's coverage: totals, then the files
# with the most untested lines. CI appends it to the job summary.
#   ruby script/coverage_summary.rb [how many files, default 25]
require "json"

root = File.expand_path("..", __dir__)
last = JSON.parse(File.read(File.join(root, "coverage/.last_run.json")))["result"]
runs = JSON.parse(File.read(File.join(root, "coverage/.resultset.json")))
files = runs.values.first["coverage"]

rows = files.filter_map do |path, data|
  lines = data["lines"].compact
  next if lines.empty?
  missed = lines.count(0)
  next if missed.zero?
  [path.delete_prefix("#{root}/"), lines.size, missed]
end

puts "### Coverage"
puts
puts "Lines: **#{last["line"]}%**" + (last["branch"] ? " · Branches: **#{last["branch"]}%**" : "")
puts
puts "Most untested lines:"
puts
puts "| File | Lines | Untested | Covered |"
puts "|---|---:|---:|---:|"
rows.sort_by { |_, _, missed| -missed }.first(Integer(ARGV[0] || 25)).each do |path, total, missed|
  puts "| `#{path}` | #{total} | #{missed} | #{((total - missed) * 100.0 / total).round}% |"
end
