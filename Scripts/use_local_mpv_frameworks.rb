#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "pathname"

ROOT = File.expand_path("..", __dir__)
SCRIPT = File.join(ROOT, "Scripts/download_mpv_frameworks.sh")

unless File.executable?(SCRIPT)
  File.chmod(0o755, SCRIPT)
end

exec(SCRIPT)
