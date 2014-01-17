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
    '***Withings***',
    'Parses Body Analyzer measurements logged by IFTTT.com',
    'withings_ifttt_input_file is a string pointing to the location of the file created by IFTTT.',
    'The recipe at https://ifttt.com/recipes/56242 determines that location.',
    '***Facebook***',
    'Parses Facebook posts logged by IFTTT.com',
    'facebook_ifttt_input_file is a string pointing to the location of the file created by IFTTT.',
    'The recipe at https://ifttt.com/recipes/56242 determines that location.',
    '***Twitter***',
    'Logs updates and favorites for specified Twitter users',
    'twitter_users should be an array of Twitter usernames, e.g. [ ttscoff, markedapp ]',
    'save_images (true/false) determines whether TwitterLogger will look for image urls and include them in the entry',
    'save_favorites (true/false) determines whether TwitterLogger will look for the favorites of the given usernames and include them in the entry',
    'save_images_from_favorites (true/false) determines whether TwitterLogger will download images for the favorites of the given usernames and include them in the entry',
    'save_retweets (true/false) determines whether TwitterLogger will include retweets in the posts for the day',
    'droplr_domain: if you have a custom droplr domain, enter it here, otherwise leave it as d.pr ',
    'digest_timeline: if true will create a single entry for all tweets',
    'twitter_oauth_token and oauth_secret should be left blank and will be filled in by the plugin'
  ],
  'foursquare_feed' => '',
  'instapaper_feeds' => [],
  'instapaper_include_content_preview' => true,
  'pinboard_feeds' => [],
  'pinboard_description' => false,
  'pinboard_save_hashtags' => true,
  'withings_ifttt_input_file' => '',
  'facebook_ifttt_input_file' => '',
  'facebook_ifttt_star' => false,
  'twitter_users' => [],
  'twitter_save_favorites' => true,
  'twitter_save_images' => true,
  'twitter_save_images_from_favorites' => true,
  'twitter_droplr_domain' => 'd.pr',
  'twitter_oauth_token' => '',
  'twitter_oauth_token_secret' => '',
  'twitter_exclude_replies' => true,
  'twitter_save_retweets' => false,
  'twitter_digest_timeline' => true
}
$slog.register_plugin({ 'class' => 'DailyLogger', 'config' => config })

require 'rexml/document'
require 'rss/dublincore'
require 'twitter'
require 'twitter_oauth'
require 'date'
require 'time'

class DailyLogger < Slogger
  require 'date'
  require 'time'

  @@daily_content = ''
  @@reading_content = ''
  @@place_content = ''
  @@bookmark_content = ''
  @@social_content = ''
  @@fitness_content = ''

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
            feedTitle = rss.channel.title.gsub(/Instapaper: /, "")
            feed_output += "* #{feedTitle} - [#{item.title}](#{item.link})\n"
            feed_output += "\n     #{content}\n" if config['instapaper_include_content_preview'] == true
          else
            # The archive orders posts inconsistenly so older items can
            # show up before newer ones
            if rss.channel.title != "Instapaper: Archive"
              break
            end
          end
        }
        output += feed_output unless feed_output == ''
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
          item_date = Time.parse(item.date.to_s) + Time.now.gmt_offset
          if item_date > @timespan
            content = ''
            post_tags = ''
            if config['pinboard_description']
              content = "   > " + item.description.gsub(/\n/, "   \n> ").strip unless item.description.nil?
              content = "#{content}\n" unless content == ''
            end
            if config['pinboard_save_hashtags']
              post_tags = "\n" + item.dc_subject.split(' ').map { |tag| "##{tag}" }.join(' ') + "\n" unless item.dc_subject.nil?
            end
            post_tags = "\n#{post_tags}\n" unless post_tags == ''
            feed_output += "* [#{item.title.gsub(/\n/, ' ').strip}](#{item.link})\n#{content}"
          else
            break
          end
        }
        output += feed_output + "\n" unless feed_output == ''
      rescue Exception => e
        puts "Error getting posts for #{rss_feed}"
        p e
        return ''
      end
    end
    unless output == ''
      @@bookmark_content = "##### Pinboard\n#{output}"
    end
  end

  # ---------------------------
  # Facebook
  # ---------------------------
  def do_facebook
    if @config.key?(self.class.name)
      config = @config[self.class.name]
        if !config.key?('facebook_ifttt_input_file') || config['facebook_ifttt_input_file'] == []
          @log.warn("DailyLogger - Facebook has not been configured or an option is invalid, please edit your slogger_config file.")
          return
        end
    else
         @log.warn("DailyLogger - Facebook has not been configured or a feed is invalid, please edit your slogger_config file.")
        return
    end

    inputFile = config['facebook_ifttt_input_file']

    @log.info("Logging FacebookIFTTTLogger posts at #{inputFile}")

    regPost = /^Post: /
    regDate = /^Date: /
    ampm    = /(AM|PM)\Z/
    pm      = /PM\Z/

    last_run = @timespan
    today = Time.new
    today = Time.local(today.year, today.month, today.day)

    ready = false
    inpost = false
    posttext = ""
    entrytext = ""
    statusline = ""

    options = {}
    options['starred'] = config['facebook_ifttt_star']

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
          ltime = Time.local(year, month, day)
          date = ltime.to_i

          if date == today.to_i
            posttext += "* #{statusline}\n"
            statusline = ""
          end

          if not posttext == ""
            options['datestamp'] = ltime.utc.iso8601
            ready = true
          end
        elsif line =~ regPost or inpost == true
          inpost = true
          line = line.gsub(regPost, "")
          statusline = line
          ready = false
        end
      end

      if ready
        if posttext != ''
        entrytext += "##### Facebook\n" + posttext + "\n"
        end
        @@social_content += entrytext unless entrytext == ''

        ready = false
        posttext = ""
      end
    end
  end

  # ---------------------------
  # Twitter
  # ---------------------------
  def get_body(target, depth = 0)

    final_url = RedirectFollower.new(target).resolve
    url = URI.parse(final_url.url)

    host, port = url.host, url.port if url.host && url.port
    req = Net::HTTP::Get.new(url.path)
    res = Net::HTTP.start(host, port) {|http| http.request(req) }

    return res.body
  end

  def single_entry(tweet)

    @twitter_config['twitter_tags'] ||= ''

    options = {}
    options['content'] = "#{tweet[:text]}\n\n-- [@#{tweet[:screen_name]}](https://twitter.com/#{tweet[:screen_name]}/status/#{tweet[:id]})\n\n#{@twitter_config['twitter_tags']}\n"
    tweet_time = Time.parse(tweet[:date].to_s)
    options['datestamp'] = tweet_time.utc.iso8601

    sl = DayOne.new

    if tweet[:images] == []
      sl.to_dayone(options)
    else
      tweet[:images].each do |imageurl|
        options['uuid'] = %x{uuidgen}.gsub(/-/,'').strip
        path = sl.save_image(imageurl,options['uuid'])
        sl.store_single_photo(path,options) unless path == false
      end
    end

    return true
  end

  def get_tweets(user,type='timeline')
    @log.info("Getting Twitter #{type} for #{user}")
    @log.info("oauth token: #{@twitter_config['twitter_oauth_token']}")
    @log.info("oauth token secret: #{@twitter_config['twitter_oauth_token_secret']}")
    client = Twitter::REST::Client.new do |config|
      config.consumer_key        = "53aMoQiFaQfoUtxyJIkGdw"
      config.consumer_secret     = "Twnh3SnDdtQZkJwJ3p8Tu5rPbL5Gt1I0dEMBBtQ6w"
      config.access_token        = @twitter_config["twitter_oauth_token"]
      config.access_token_secret = @twitter_config["twitter_oauth_token_secret"]
    end

    case type

      when 'favorites'
        params = { "count" => 250, "screen_name" => user, "include_entities" => true }
        tweet_obj = client.favorites(params)

      when 'timeline'
        params = { "count" => 250, "screen_name" => user, "include_entities" => true, "exclude_replies" => @twitter_config['twitter_exclude_replies'], "include_rts" => @twitter_config['twitter_save_retweets']}
        tweet_obj = client.user_timeline(params)

    end

    images = []
    tweets = []
    begin
      tweet_obj.each { |tweet|
        today = @timespan
        tweet_date = tweet.created_at
        break if tweet_date < today
        tweet_text = tweet.text.gsub(/\n/,"\n\t")
        screen_name = user
        if type == 'favorites'
          # TODO: Prepend favorite's username/link
          screen_name = tweet.user.status.user.screen_name
          tweet_text = "[#{screen_name}](http://twitter.com/#{screen_name}): #{tweet_text}"
        end

        tweet_id = tweet.id
        unless tweet.urls.empty?
          tweet.urls.each { |url|
            tweet_text.gsub!(/#{url.url}/,"[#{url.display_url}](#{url.expanded_url})")
          }
        end
        begin
          if @twitter_config['twitter_save_images']
            tweet_images = []
            unless tweet.media.empty?
              tweet.media.each { |img|
                tweet_images.push(img.media_url.to_s)
              }
            end

              # new logic for the picture links and added yfrog (nr)
            tweet_text.scan(/\((http:\/\/twitpic.com\/\w+?)\)/).each do |picurl|
              aurl=URI.parse(picurl[0])
              burl="http://twitpic.com/show/large#{aurl.path}"
              curl = RedirectFollower.new(burl).resolve
              final_url=curl.url
              tweet_images.push(final_url) unless final_url.nil?
              #tweet_images=[tweet_text,tweet_date.utc.iso8601,final_url] unless final_url.nil?
            end
            tweet_text.scan(/\((http:\/\/campl.us\/\w+?)\)/).each do |picurl|
              aurl=URI.parse(picurl[0])
              burl="http://campl.us/#{aurl.path}:800px"
              curl = RedirectFollower.new(burl).resolve
              final_url=curl.url
              tweet_images.push(final_url) unless final_url.nil?
            end

            tweet_text.scan(/\((http:\/\/instagr\.am\/\w\/.+?\/)\)/).each do |picurl|
              final_url=self.get_body(picurl[0]).match(/http:\/\/distilleryimage.*?\.com\/[a-z0-9_]+\.jpg/)
              tweet_images.push(final_url[0]) unless final_url.nil?
            end
            tweet_text.scan(/http:\/\/[\w\.]*yfrog\.com\/[\w]+/).each do |picurl|
              aurl=URI.parse(picurl)
              burl="http://yfrog.com#{aurl.path}:medium"
              curl = RedirectFollower.new(burl).resolve
              final_url=curl.url
              tweet_images.push(final_url) unless final_url.nil?
            end
          end
        rescue Exception => e
          @log.warn("Failure gathering image urls")
          p e
        end

        if tweet_id
          tweets.push({:text => tweet_text, :date => tweet_date, :screen_name => screen_name, :images => tweet_images, :id => tweet_id})
        end
      }
      return tweets
    rescue Exception => e
      @log.warn("Error getting #{type} for #{user}")
      p e
      return []
    end

  end

  def do_twitter
    if @config.key?(self.class.name)
        @twitter_config = @config[self.class.name]
        if !@twitter_config.key?('twitter_users') || @twitter_config['twitter_users'] == []
          @log.warn("Twitter users have not been configured, please edit your slogger_config file.")
          return
        end
    else
      @log.warn("Twitter users have not been configured, please edit your slogger_config file.")
      return
    end

    if @twitter_config['twitter_oauth_token'] == '' || @twitter_config['twitter_oauth_token_secret'] == ''
      client = TwitterOAuth::Client.new(
          :consumer_key => "53aMoQiFaQfoUtxyJIkGdw",
          :consumer_secret => "Twnh3SnDdtQZkJwJ3p8Tu5rPbL5Gt1I0dEMBBtQ6w"
      )

      request_token = client.authentication_request_token(
        :oauth_callback => 'oob'
      )
      @log.info("Twitter requires configuration, please run from the command line and follow the prompts")
      puts
      puts "------------- Twitter Configuration --------------"
      puts "Slogger will now open an authorization page in your default web browser. Copy the code you receive and return here."
      print "Press Enter to continue..."
      gets
      %x{open "#{request_token.authorize_url}"}
      print "Paste the code you received here: "
      code = gets.strip

      access_token = client.authorize(
        request_token.token,
        request_token.secret,
        :oauth_verifier => code
      )
      if client.authorized?
        @twitter_config['twitter_oauth_token'] = access_token.params["oauth_token"]
        @twitter_config['twitter_oauth_token_secret'] = access_token.params["oauth_token_secret"]
        puts
        log.info("Twitter successfully configured, run Slogger again to continue")
        @log.info("oauth_token: " + access_token.params["oauth_token"])
        @log.info("oauth_token_secret: " + access_token.params["oauth_token_secret"])
        return @twitter_config
      end
    end
    @twitter_config['twitter_save_images'] ||= true
    @twitter_config['twitter_droplr_domain'] ||= 'd.pr'
    @twitter_config['twitter_digest_timeline'] ||= true

    @twitter_config['twitter_tags'] ||= '#social #twitter'
    tags = "\n\n#{@twitter_config['twitter_tags']}\n" unless @twitter_config['twitter_tags'] == ''

    twitter_content = ''
    entrytext = ''

    @twitter_config['twitter_users'].each do |user|

      tweets = try { self.get_tweets(user, 'timeline') }

      if @twitter_config['twitter_save_favorites']
        favs = try { self.get_tweets(user, 'favorites')}
      else
        favs = []
      end

      unless tweets.empty?
        if @twitter_config['twitter_digest_timeline']
          content = "*@#{user}*\n"
          content << digest_entry(tweets, tags)
          twitter_content += content unless content == ''
          if @twitter_config['twitter_save_images']
            tweets.select {|t| !t[:images].empty? }.each {|t| self.single_entry(t) }
          end
        end

      end
      unless favs.empty?
        content = "*@#{user}'s* Favorite Tweets\n"
        content << digest_entry(favs, tags)
        twitter_content += content unless content == ''
      end
    end

    if twitter_content != ''
      entrytext = "##### Twitter\n" + twitter_content + "\n"
    end
    @@social_content += entrytext unless entrytext == ''

    return @twitter_config
  end

  def digest_entry(tweets, tags)
    tweets.reverse.map do |t|
      "* [[#{t[:date].strftime(@time_format)}](https://twitter.com/#{t[:screen_name]}/status/#{t[:id]})] #{t[:text]}\n"
    end.join("\n") << "\n"
  end

  def try(&action)
    retries = 0
    success = false
    until success || $options[:max_retries] == retries
      result = yield
      if result
        success = true
      else
        retries += 1
        @log.error("Error performing action, retrying (#{retries}/#{$options[:max_retries]})")
        sleep 2
      end
    end
    result
  end

  # ---------------------------
  # Withings
  # ---------------------------
  def do_withings
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
    entrytext = ""

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
            posttext += "* Weight: " + line
            ready = false
        elsif line =~ regLeanMassLb
            line = line.gsub(regLeanMassLb, "")
            posttext += "* Lean Mass: " + line
            ready = false
        elsif line =~ regFatMassLb
            line = line.gsub(regFatMassLb, "")
            posttext += "* Fat Mass: " + line
            ready = false
        elsif line =~ regFatPercent
            line = line.gsub(regFatPercent, "")
            posttext += "* BMI: " + line
            ready = false
        end

        if ready
          if posttext != ''
            entrytext = "##### Withings Body Analyzer\n" + posttext + "\n"
          end
          @@fitness_content += entrytext unless entrytext == ''

          ready = false
          posttext = ""
        end
      end
    end
  end

  # ---------------------------
  # Reading
  # ---------------------------
  def do_reading
    content = ''

    do_instapaper

    if @@reading_content != ''
      content += "### Reading\n\n" + @@reading_content + "\n"
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
      content += "### Places\n\n" + @@place_content + "\n"
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
      content += "### Bookmarks\n\n" + @@bookmark_content + "\n"
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
      content += "### Social\n\n" + @@social_content + "\n"
    end
    @@daily_content += content unless content == ''
  end

  # ---------------------------
  # Fitness
  # ---------------------------
  def do_fitness
    content = ''

    do_withings

    if @@fitness_content != ''
      content += "### Fitness\n\n" + @@fitness_content + "\n"
    end
    @@daily_content += content unless content == ''
  end

  # ---------------------------
  # Log to Dayone
  # ---------------------------
  def do_log
    do_social
    do_fitness
    do_places
    do_reading
    do_bookmarks

    options = {}
    options['content'] = @@daily_content
    DayOne.new.to_dayone(options)
  end
end
