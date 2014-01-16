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
    'Find the RSS feed for any folder at the bottom of a web interface page',
    '***Pinboard***',
    'Logs bookmarks for today from Pinboard.in.',
    'pinboard_feeds is an array of one or more Pinboard RSS feeds',
    'pinboard_digest true will group all new bookmarks into one post, false will split them into individual posts dated when the bookmark was created'
  ],
  'foursquare_feed' => '',
  'instapaper_feeds' => [],
  'instapaper_include_content_preview' => true,
  'pinboard_feeds' => [],
  'pinboard_save_hashtags' => true,
  'pinboard_digest' => true
}
$slog.register_plugin({ 'class' => 'DailyLogger', 'config' => config })

require 'rexml/document'
require 'rss/dublincore'

class DailyLogger < Slogger
    @@daily_content = ''
    @@reading_content = ''
    @@place_content = ''
    @@bookmark_content = ''
    @@social_content = ''

  # ---------------------------
  # Instapaper
  # ---------------------------
  def do_instapaper
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
      @@reading_content += "##### Instapaper\n#{output}"
    end
  end

  # ---------------------------
  # Foursquare
  # ---------------------------
  def do_foursquare
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
      entrytext = "##### Foursquare\n" + content
    end
    @@place_content += entrytext unless entrytext == ''
  end

  # ---------------------------
  # Pinboard
  # ---------------------------
  def do_pinboard
    if @config.key?(self.class.name)
      config = @config[self.class.name]
      if !config.key?('pinboard_feeds') || config['pinboard_feeds'] == [] || config['pinboard_feeds'].empty?
        @log.warn("Pinboard feeds have not been configured, please edit your slogger_config file.")
        return
      end
    else
      @log.warn("Pinboard feeds have not been configured, please edit your slogger_config file.")
      return
    end

    today = @timespan.to_i

    @log.info("Getting Pinboard bookmarks for #{config['pinboard_feeds'].length} feeds")
    output = ''

    config['pinboard_feeds'].each do |rss_feed|
      begin
        rss_content = ""
        open(rss_feed) do |f|
          rss_content = f.read
        end

        rss = RSS::Parser.parse(rss_content, false)
        feed_output = ''
        rss.items.each { |item|
          feed_output = '' unless config['pinboard_digest']
          item_date = Time.parse(item.date.to_s) + Time.now.gmt_offset
          if item_date > @timespan
            content = ''
            post_tags = ''
            if config['pinboard_digest']
              content = "\n        " + item.description.gsub(/\n/, "\n        ").strip unless item.description.nil?
            else
              content = "\n> " + item.description.gsub(/\n/, "\n> ").strip unless item.description.nil?
            end
            content = "\n#{content}\n" unless content == ''
            if config['pinboard_save_hashtags']
              post_tags = "\n" + item.dc_subject.split(' ').map { |tag| "##{tag}" }.join(' ') + "\n" unless item.dc_subject.nil?
            end
            post_tags = "\n#{post_tags}\n" unless post_tags == ''
            feed_output += "#{config['pinboard_digest'] ? '* ' : ''}[#{item.title.gsub(/\n/, ' ').strip}](#{item.link})\n#{content}#{post_tags}"
          else
            break
          end
          output = feed_output unless config['pinboard_digest']
          unless output == '' || config['pinboard_digest']
            @@bookmark_content = "##### Pinboard\n#{output}"
          end
        }
        output += "### [#{rss.channel.title}](#{rss.channel.link})\n\n" + feed_output + "\n" unless feed_output == ''
      rescue Exception => e
        puts "Error getting posts for #{rss_feed}"
        p e
        return ''
      end
    end
    unless output == '' || !config['pinboard_digest']
      @@bookmark_content = "##### Pinboard\n#{output}"
    end
  end

  # ---------------------------
  # Facebook
  # ---------------------------
  def do_facebook

  end

  # ---------------------------
  # Twitter
  # ---------------------------
  def do_twitter

  end


  # ---------------------------
  # Reading
  # ---------------------------
  def do_reading
    content = ''

    do_instapaper

    if @@reading_content != ''
      content += "### Reading\n\n" + @@reading_content
    end
    @@daily_content += content unless content == ''
  end

  # ---------------------------
  # Places
  # ---------------------------
  def do_places
    content = ''

    do_foursquare

    if @@place_content != ''
      content += "### Places\n\n" + @@place_content
    end
    @@daily_content += content unless content == ''
  end

  # ---------------------------
  # Bookmarks
  # ---------------------------
  def do_bookmarks
    content = ''

    do_pinboard

    if @@bookmark_content != ''
      content += "### Bookmarks\n\n" + @@bookmark_content
    end
    @@daily_content += content unless content == ''
  end

  # ---------------------------
  # Social
  # ---------------------------
  def do_social
    content = ''

    do_facebook
    do_twitter

    if @@social_content != ''
      content += "### Social\n\n" + @@social_content
    end
    @@daily_content += content unless content == ''
  end

  # ---------------------------
  # Log to Dayone
  # ---------------------------
  def do_log
    do_social
    do_places
    do_reading
    do_bookmarks

    options = {}
    options['content'] = @@daily_content
    DayOne.new.to_dayone(options)
  end
end
