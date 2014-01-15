=begin
Plugin: Withings / IFTTT logger
Description: Parses Body Analyzer logged by IFTTT.com
Author: [hargrove](https://github.com/spiritofnine)
Configuration:
  withings_ifttt_input_file: "/path/to/dropbox/ifttt/withings.md"
Notes:
  - Configure IFTTT to log Body analyzer measurements to a text file.
  - You can use the recipe at https://ifttt.com/recipes/56242
  - and personalize if for your Dropbox set up.
  -
  - Unless you change it, the recipe will write to the following
  - location:
  -
  - {Dropbox path}/Apps/IFTTT/fitness/fitness.md.txt
  -
  - You probably don't want that, so change it in the recipe accordingly.
  -
  - On a standard Dropbox install on OS X, the Dropbox path is
  -
  - /Users/username/Dropbox
  -
  - so the full path is:
  -
  - /Users/username/Dropbox/Apps/IFTTT/fitness/fitness.md.txt
  -
  - You should set withings_ifttt_input_file to this value, substituting username appropriately.
=end

require 'date'

config = {
  'description' => ['Parses Body Analyzer measurements logged by IFTTT.com',
                    'withings_ifttt_input_file is a string pointing to the location of the file created by IFTTT.',
                    'The recipe at https://ifttt.com/recipes/56242 determines that location.'],
  'withings_ifttt_input_file' => '',
  'withings_ifttt_tags' => '#fitness'
}

$slog.register_plugin({ 'class' => 'WithingsIFTTTLogger', 'config' => config })

class WithingsIFTTTLogger < Slogger
  require 'date'
  require 'time'

  def do_log
    if @config.key?(self.class.name)
      config = @config[self.class.name]
      if !config.key?('withings_ifttt_input_file') || config['withings_ifttt_input_file'] == []
        @log.warn("WithingsIFTTTLogger has not been configured or an option is invalid, please edit your slogger_config file.")
        return
      end
    else
      @log.warn("WithingsIFTTTLogger has not been configured or a feed is invalid, please edit your slogger_config file.")
      return
    end

    tags = config['withings_ifttt_tags'] || ''
    tags = "\n\n#{tags}\n" unless @tags == ''

    inputFile = config['withings_ifttt_input_file']

    @log.info("Logging WithingsIFTTTLogger posts at #{inputFile}")

    regWeightLb = /^WeightLb: /
    regLeanMassLb = /^LeanMassLb: /
    regFatMassLb = /^FatMassLb: /
    regFatPercent = /^FatPercent: /
    regDate = /^Date: /
    ampm    = /(AM|PM)\Z/
    pm      = /PM\Z/

    last_run = @timespan

    ready = false
    inpost = false
    posttext = ""

    options = {}

    f = File.new(File.expand_path(inputFile))
    content = f.read
    f.close

    if !content.empty?
      each_selector = RUBY_VERSION < "1.9.2" ? :each : :each_line
      content.send(each_selector) do | line|
        if line =~ regDate
          inpost = false
          line = line.strip
          line = line.gsub(regDate, "")
          line = line.gsub(" at ", ' ')
          line = line.gsub(',', '')

          month, day, year, time = line.split
          parseTime = DateTime.parse(time).strftime("%H:%M")
          hour,min = parseTime.split(/:/)

          month = Date::MONTHNAMES.index(month)
          ltime = Time.local(year, month, day, hour, min, 0, 0)
          date = ltime.to_i

          if not date > last_run.to_i
            posttext = ""
            next
          end

          options['datestamp'] = ltime.utc.iso8601
          ready = true
        elsif line =~ regWeightLb
            line = line.gsub(regWeightLb, "")
            posttext += "* Weight: " + line + "\n"
            ready = false
        elsif line =~ regLeanMassLb
            line = line.gsub(regLeanMassLb, "")
            posttext += "* Lean Mass: " + line + "\n"
            ready = false
        elsif line =~ regFatMassLb
            line = line.gsub(regFatMassLb, "")
            posttext += "* Fat Mass: " + line + "\n"
            ready = false
        elsif line =~ regFatPercent
            line = line.gsub(regFatPercent, "")
            posttext += "* BMI: " + line + "\n"
            ready = false
        end

        if ready
          sl = DayOne.new
          options['content'] = "## Fitness\n\n### Withings Body Analyzer\n#{posttext}\n\n#{tags}"
          sl.to_dayone(options)
          ready = false
          posttext = ""
        end
      end
    end
  end
end
