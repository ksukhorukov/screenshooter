#!/usr/bin/env ruby

require 'json'

class String
  def valid_json?
    begin
      JSON.parse(self)
      return true
    rescue Exception => e
      return false
    end
  end
end

def check_availability(filename)
	File.exists?(filename) and File.readable?(filename)
end

def execute_ffmpeg(command)
  STDOUT.sync = true
  command = "#{command} 2>&1"
  progress = nil
  exit_status = 0
  duration, duration_seconds, ellapsed_time, ellapsed_seconds, percentage = nil
  last_line = nil
  IO.popen(command) do |pipe|
    pipe.each("\r") do |line|
      if line =~ /Duration:(\s.?(\d*):(\d*):(\d*\.\d*))/
        duration = $2.to_s + ":" + $3.to_s + ":" + $4.to_s
        duration_seconds = ($2.to_f * 60 * 60) + ($3.to_f * 60) + ($4.to_f + $5.to_f / 100)
      end
      if line =~ /^frame=.*time=(\d{2}):(\d{2}):(\d{2}).(\d{2})/
        ellapsed_time = $1.to_s + ':' + $2.to_s + ':' + $3.to_s + '.' + $4.to_s
        ellapsed_seconds = ($1.to_f * 60 * 60) + ($2.to_f * 60) + $3.to_f + ($4.to_f / 100)
        #puts "#{ellapsed_time} (#{ellapsed_seconds})"
        percentage = ((ellapsed_seconds / duration_seconds) * 100).round
        #print progress_bar(percentage)
      end
      last_line = line #it will be use to output an error in case of any failure
    end
  end
  raise last_line if $?.exitstatus != 0
end


def get_video_resolution(file_name)
  command = "ffprobe -show_streams \"#{file_name}\" 2>&1"
  width = nil
  height = nil
  IO.popen(command) do |pipe|
    pipe.each("\r") do |line|
      if line =~ /width=(\d+)/
        width = $1.to_i
      end
      if line =~ /height=(\d+)/
        height = $1.to_i
      end
    end
  end
  [width*height, "#{width}x#{height}"]
end

def get_video_duration(file_name)
  command = "ffprobe -show_streams \"#{file_name}\" 2>&1 | grep duration"
  duration = nil
  IO.popen(command) do |pipe|
    pipe.each("\n") do |line|
      if line =~ /duration=(\d+\.\d+)/
        if duration.nil?
          duration = $1.to_f
        elsif $1.to_f > duration
          duration = $1.to_f
        end
      end
    end
  end
  #duration in milliseconds
  (duration * 1000).round
end


unless ARGV.count == 1
	conf = 'config.json'
else
	conf = ARGV.first
end

unless check_availability conf
	puts "Error: Cannot open configuration file: '#{conf}'"
	exit
end

conf_json = File.readlines(conf).join

unless conf_json.valid_json?
	puts "Error: Invalid JSON sysntax in '#{conf}'"
	exit
end

config = JSON.parse(conf_json)
used_names = []
required_params = %w(name resolution timestamp)

#start of data validation

config.each do |filepath, settings|

	unless check_availability filepath
		puts "Error: '#{filepath}' does not exists or not readable."
		exit
	end
	unless (settings.keys & required_params).size == required_params.size
		puts "Error: '#{filepath}' configuration section does not contain all of the required params - name, resolution and timestamp."
		exit
	end

	if used_names.include? settings['name']
		puts "Error: duplicate entry of screenshot name '#{settings['name']}'"
		exit
	else
		used_names << settings['name']
		screen_name = settings['name']
	end

	if settings['resolution'] =~ /(\d+)x(\d+)/
		actual_resolution = get_video_resolution filepath
		if ($1.to_i * $2.to_i) > actual_resolution[0]
			puts "Error: #{settings['resolution']} is bigger than actual resolution of the '#{filepath}' - #{actual_resolution[1]}"
			exit
		else
			resolution = settings['resolution']
		end
	else
		puts "Error: wrong resolution format '#{settings['resolution']}'"
		exit
	end

	if settings['timestamp'] =~ /^(\d+)$/
		actual_duration = get_video_duration filepath
		timestamp = $1.to_i
		if timestamp > actual_duration
			puts "Error: timestamp #{timestamp}ms is bigger than actual duration (#{actual_duration}ms) of '#{filepath}'."
			exit
		end
	else
		puts "Error: incorrect duration '#{settings['duration']}' for the '#{filepath}'. Duration must be integer in milliseconds."
		exit
	end

end

#end of data validation, starting screenshot capturing 
if used_names.count > 0
	puts "[+] Starting screenshot capturing..."
	counter = 0
	config.each do |filepath, settings|
		counter += 1
		screen_name = settings['name'] + '.jpg'
		resolution = settings['resolution']
		timestamp = settings['timestamp'].to_f / 1000.0

		ffmpeg_command = "ffmpeg -ss #{timestamp} -i #{filepath} -y -f image2 -vcodec mjpeg -vframes 1 #{screen_name}"

		execute_ffmpeg(ffmpeg_command)

		puts "#{counter}) #{screen_name}"

	end
	puts "[+] Done!"
else 
	puts "Nothing to convert! Check your 'config.json' file please"
end







