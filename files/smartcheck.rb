#!/usr/bin/env ruby

require 'net/http'
require 'json'

def get_smart_data(drive)
	`/usr/sbin/smartctl -a #{drive}`
end

class SmartChecker

	CHECKS = ['summary', 'relocated_sectors', 'uncorrectable_errors', 'uncorrectable_sector', 'command_timeout', 'bad_block']
	PASS = 'pass'
	FAIL = 'fail'
	SKIP = 'skip'

	def initialize(smart_data, overrides)
		@smart_data = smart_data
		@overrides = Hash[overrides.map{|key,val| [key.to_i,val.to_s] } ]
	end

	def check
		results = {}
		CHECKS.each do |c|
			check = 'check_'+c
			results[check] = self.method(check).call
		end
		puts results
		return results.values.all? { |c| c == PASS or c == SKIP }
	end

	def check_summary
		m = /SMART overall-health self-assessment test result: (.*)/.match @smart_data
		if m
			if m[1] == 'PASSED'
				return PASS
			end
		end
		return FAIL
	end

	def check_relocated_sectors
		check_attr_is_zero_or_absent(5)
	end

	def check_uncorrectable_errors
		check_attr_is_zero_or_absent(187)
	end

	def check_command_timeout
		check_attr_is_zero_or_absent(188)
	end

	def check_uncorrectable_sector
		check_attr_is_zero_or_absent(198)
	end

	def check_bad_block
		check_attr_is_zero_or_absent(183)
	end

	def check_attr_is_zero_or_absent(id)
		attr = get_vendor_table_attr(id)
		return SKIP if attr.nil?
		return PASS if @overrides.has_key? id and attr == @overrides[id]
		return PASS if attr == '0'
		return FAIL
	end

	def check_attr_is_zero(id)
		return PASS if '0' == get_vendor_table_attr(id)
		return FAIL
	end

	def get_vendor_table_attr(id)
		t = get_vendor_table
		row = /^\s*#{id}\s.*$/.match(t)
		if row
			cols = row[0].split
			if cols.length == 10
				return cols[9]
			end
		end
	end

	def get_vendor_table
		if @m
			return @m
		else
			m = /Vendor Specific SMART Attributes with Thresholds:.*?^\s*$/m.match(@smart_data)
			if m
				@m = m[0]
				return @m
			end
		end
	end
end

def check(drive,snitch,overrides)
	smartdata = get_smart_data drive
	c = SmartChecker.new smartdata, overrides
	if c.check
		res = Net::HTTP.get_response(URI("https://nosnch.in/#{snitch}"))
		puts "Reported okay for #{drive} to snitch #{snitch}"
	else
		puts "Not dialing into snitch #{snitch} as something is wrong with drive #{drive}"
	end
end


whitelisted_drives_and_snitches = {}

json = nil

File.open(ARGV[0], "r") do |f|
	json = JSON.parse(f.read)
end

json.each do |entry|
	if File.exist? entry['drive']
		check(entry['drive'], entry['snitch'], entry['overrides'] || {})
	end
end

# vim: noexpandtab
