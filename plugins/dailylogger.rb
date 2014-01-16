=begin
Plugin: Daily Logger
Version: 1.0
Description: Logs daily activities in a single dayone post
Notes:
  instapaper_feeds is an array of Instapaper RSS feeds
  - Find the RSS feed for any folder at the bottom of the web interface page for that folder
Author: [Brett Terpstra](http://brettterpstra.com)
Configuration:
  instapaper_feeds: [ 'http://www.instapaper.com/rss/106249/XXXXXXXXXXXXXX']
  instapaper_tags: "#social #reading"
Notes:

=end
config = {
  'description' => [
    '***Foursquare***',
    'foursquare_feed must refer to the address of your personal feed.',
    'Your feed should be available at <https://foursquare.com/feeds/>',
    '***Instapaper***',
    'Logs today\'s posts to Instapaper.',
    'instapaper_feeds is an array of one or more RSS feeds',
    'Find the RSS feed for any folder at the bottom of a web interface page'
  ],
  'foursquare_feed' => '',
  'instapaper_feeds' => [],
  'instapaper_include_content_preview' => true,
  'instapaper_tags' => '#social #reading'
}
$slog.register_plugin({ 'class' => 'DailyLogger', 'config' => config })

require 'rexml/document'

class DailyLogger < Slogger
    daily_content = ''

  # ---------------------------
  # Instapaper
  # ---------------------------
  def do_log
    if @config.key?(self.class.name)
      config = @config[self.class.name]
      if !config.key?('instapaper_feeds') || config['instapaper_feeds'] == [] || config['instapaper_feeds'].empty?
        @log.warn("Instapaper feeds have not been configured, please edit your slogger_config file.")
        return
      end
    else
      @log.warn("Instapaper feeds have not been configured, please edit your slogger_config file.")
      return
    end

    sl = DayOne.new
    config['instapaper_tags'] ||= ''
    tags = "\n\n#{config['instapaper_tags']}\n" unless config['instapaper_tags'] == ''
    today = @timespan.to_i

    @log.info("Getting Instapaper posts for #{config['instapaper_feeds'].length} accounts")
    output = ''

    config['instapaper_feeds'].each do |rss_feed|
      begin
        rss_content = ""
        open(rss_feed) do |f|
          rss_content = f.read
        end

        rss = RSS::Parser.parse(rss_content, false)
        feed_output = ''
        rss.items.each { |item|
          item_date = Time.parse(item.pubDate.to_s)
          # Instapaper shows times in GMT, but doesn't display that in pubDate,
          # which means Time.parse will parse it as the local time and potentially
          # missing some items. Subtracting the gmt_offset fixes this.
          if item_date > (@timespan - item_date.gmt_offset)
            content = item.description.gsub(/\n/,"\n    ") unless item.description == ''
            feed_output += "* #{rss.channel.title} - [#{item.title}](#{item.link})\n"
            feed_output += "\n     #{content}\n" if config['instapaper_include_content_preview'] == true
          else
            # The archive orders posts inconsistenly so older items can
            # show up before newer ones
            if rss.channel.title != "Instapaper: Archive"
              break
            end
          end
        }
        output += feed_output + "\n" unless feed_output == ''
      rescue Exception => e
        raise "Error getting posts for #{rss_feed}"
        p e
        return ''
      end
    end
    unless output.strip == ''
      daily_content += "##### Instapaper\n#{output}"
    end
  end

  # ---------------------------
  # Foursquare
  # ---------------------------
  def do_log
    if @config.key?(self.class.name)
      config = @config[self.class.name]
      if !config.key?('foursquare_feed') || config['foursquare_feed'] == ''
        @log.warn("Foursquare feed has not been configured, please edit your slogger_config file.")
        return
      else
        @feed = config['foursquare_feed']
      end
    else
      @log.warn("Foursquare feed has not been configured, please edit your slogger_config file.")
      return
    end

    @log.info("Getting Foursquare checkins")

    config['foursquare_tags'] ||= ''
    @tags = "\n\n#{config['foursquare_tags']}\n" unless config['foursquare_tags'] == ''
    @debug = config['debug'] || false

    entrytext = ''
    rss_content = ''
    begin
      url = URI.parse(@feed)

      http = Net::HTTP.new url.host, url.port
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.use_ssl = true

      res = nil

      http.start do |agent|
        rss_content = agent.get(url.path).read_body
      end

    rescue Exception => e
      @log.error("ERROR fetching Foursquare feed")
      # p e
    end
    content = ''
    rss = RSS::Parser.parse(rss_content, false)
    rss.items.each { |item|
      break if Time.parse(item.pubDate.to_s) < @timespan
      checkinDate = item.pubDate.strftime("%H:%M%p")
      content += "* #{checkinDate} - [#{item.title}](#{item.link})\n"
    }
    if content != ''
      entrytext = "### Places\n\n" + content
    end
    daily_content += entrytext unless entrytext == ''
  end

  # ---------------------------
  # Log to Dayone
  # ---------------------------
  def do_log
    options = {}
    options['content'] = daily_content
    DayOne.new.to_dayone(options)
  end
end
