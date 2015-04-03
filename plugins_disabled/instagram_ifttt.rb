=begin
Plugin: Instagram IFTTT
Description: Brief description (one line)
Author: [Ryan M](http://ryanmo.co)
Configuration:
  'ifttt_file_path': ''
  'instagram_tags': '#social #instagram'
Notes:
  - Instagram txt file
  - This will take a txt file of img url, caption and date posted
=end

require 'fileutils'

config = { # description and a primary key (username, url, etc.) required
  'description' => ['Instagram txt file',
                    'This will take a txt file of img url, caption and date posted'],
  'ifttt_file_path' => '',
  'instagram_tags' => '#social #instagram'
}
# Update the class key to match the unique classname below
$slog.register_plugin({ 'class' => 'Instagram', 'config' => config })

# unique class name: leave '< Slogger' but change ServiceLogger (e.g. LastFMLogger)
class Instagram < Slogger
  # every plugin must contain a do_log function which creates a new entry using the DayOne class (example below)
  # @config is available with all of the keys defined in "config" above
  # @timespan and @dayonepath are also available
  # returns: nothing
  def do_log
    if @config.key?(self.class.name)
      config = @config[self.class.name]
      # check for a required key to determine whether setup has been completed or not
      if !config.key?('ifttt_file_path') || config['ifttt_file_path'] == []
        @log.warn("Instagram has not been configured or an option is invalid, please edit your slogger_config file.")
        return
      else
        # set any local variables as needed
        ifttt_file_path = config['ifttt_file_path']
      end
    else
      @log.warn("Instagram has not been configured or a feed is invalid, please edit your slogger_config file.")
      return
    end
    @log.info("Logging Instagram posts")

    today = @timespan

    # Perform necessary functions to retrieve posts

    # create an options array to pass to 'to_dayone'
    # all options have default fallbacks, so you only need to create the options you want to specify

    #Get the images from the files for Instagram
    def create_content(file)
      if @config.key?(self.class.name)
        config = @config[self.class.name]
      end
      config['instagram_tags'] ||= ''
      @tags = "\n\n#{config['instagram_tags']}\n" unless config['instagram_tags'] == ''
      file_name = file
      file_read = File.readlines(file_name)

      file_read.each do |item|
        item.strip()
      end

      #
      #   This is to assume that the file reads like this:
      #   File URL
      #   Instagram comment
      #   Date posted
      #
      image_url = file_read[0]

      if image_url.match('ift.tt')
         image_url = Net::HTTP.get_response(URI.parse(image_url))['location']
      end

      image_caption = file_read[1]
      date_posted = Time.parse(file_read[-1])

      options = {}
      options['datestamp'] = date_posted.utc.iso8601
      options['starred'] = false
      options['uuid'] = %x{uuidgen}.gsub(/-/,'').strip
      options['content'] = "## Instagram Photo\n\n#{image_caption}#{@tags}"

      sl = DayOne.new
      sl.save_image(image_url,options['uuid']) if image_url
      sl.to_dayone(options)
    end

    file_path = config['ifttt_file_path']

    Dir.glob(file_path + '/*.txt') do |inst_file|
      self.create_content(inst_file)
      unless File.directory?(file_path + '/logged/')
        FileUtils.mkdir_p(file_path + '/logged/')
      end
      FileUtils.mv(inst_file, file_path + '/logged/' + File.basename(inst_file))
    end

  end

end
