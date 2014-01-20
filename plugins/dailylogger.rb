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
    'twitter_oauth_token and oauth_secret should be left blank and will be filled in by the plugin',
    '***Last.fm***',
    'Logs songs scrobbled for time period.',
    'lastfm_user is your Last.fm username.',
    'lastfm_feeds is an array that determines whether it grabs recent tracks, loved tracks, or both',
    'lastfm_include_timestamps (true/false) will add a timestamp prefix based on @time_format to each song',
    '***Github***',
    'Logs daily Github activity for the specified user',
    'github_user should be your Github username',
    '***Gist***',
    'Logs daily Gists for the specified user',
    'gist_user should be your Github username',
    '***SoundCloud***',
    'Logs SoundCloud uploads as a digest',
    'soundcloud_id is a string of numbers representing your user ID',
    'Dashboard -> Tracks, view page source and search for "trackOwnerId"',
    'soundcloud_starred is true or false, determines whether SoundCloud uploads are starred entries'
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
  'twitter_digest_timeline' => true,
  'lastfm_include_timestamps' => false,
  'lastfm_user' => '',
  'lastfm_feeds' => ['recent', 'loved'],
  'github_user' => '',
  'gist_user' => '',
  'soundcloud_id' => '',
  'soundcloud_starred' => false
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
  @@music_content = ''
  @@code_content = ''

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
      @@reading_content += "##### Instapaper\n" + output + "\n"
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
      entrytext = "##### Foursquare\n" + content + "\n"
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
              content = "\n#{content}\n" unless content == ''
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
      @@bookmark_content = "##### Pinboard\n" + output + "\n"
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
  # Last.fm
  # ---------------------------
  def get_fm_feed(feed)
    begin
      rss_content = false
      feed_url = URI.parse(feed)
      feed_url.open do |f|
        rss_content = f.read
      end
      return rss_content
    rescue
      return false
    end
  end

  def do_lastfm
    if @config.key?(self.class.name)
      config = @config[self.class.name]
      if !config.key?('lastfm_user') || config['lastfm_user'] == ''
        @log.warn("Last.fm has not been configured, please edit your slogger_config file.")
        return
      else
        feeds = config['feeds']
      end
    else
      @log.warn("Last.fm has not been configured, please edit your slogger_config file.")
      return
    end

    config['lastfm_feeds'] ||= ['recent', 'loved']

    feeds = []
    feeds << {'title'=>"Listening To", 'feed' => "http://ws.audioscrobbler.com/2.0/user/#{config['lastfm_user']}/recenttracks.rss?limit=100"} if config['lastfm_feeds'].include?('recent')
    feeds << {'title'=>"Loved Tracks", 'feed' => "http://ws.audioscrobbler.com/2.0/user/#{config['lastfm_user']}/lovedtracks.rss?limit=100"} if config['lastfm_feeds'].include?('loved')

    today = @timespan

    @log.info("Getting Last.fm playlists for #{config['lastfm_user']}")

    feeds.each do |rss_feed|
      entrytext = ''
      rss_content = try { get_fm_feed(rss_feed['feed'])}
      unless rss_content
        @log.error("Failed to retrieve #{rss_feed['title']} for #{config['lastfm_user']}")
        break
      end
      content = ''
      rss = RSS::Parser.parse(rss_content, false)

      # define a hash to store song count and a hash to link song title to the last.fm URL
      songs_count = {}
      title_to_link = {}

      rss.items.each { |item|
        timestamp = Time.parse(item.pubDate.to_s)
        break if timestamp < today
        ts = config['lastfm_include_timestamps'] ? "[#{timestamp.strftime(@time_format)}] " : ""
        title = ts + String(item.title).e_link()
        link = String(item.link).e_link()

        # keep track of URL for each song title
        title_to_link[title] = link

        # store play counts in hash
        if songs_count[title].nil?
          songs_count[title] = 1
        else
          songs_count[title] += 1
        end
      }

      # loop over each song and make final output as appropriate
      # (depending on whether there was 1 play or more)
      songs_count.each { |k, v|

        # a fudge because I couldn't seem to access this hash value directly in
        # the if statement
        link = title_to_link[k]

        if v == 1
          content += "* [#{k}](#{link})\n"
        else
          content += "* [#{k}](#{link}) (#{v} plays)\n"
        end
      }

      if content != ''
        entrytext = "##### Last.fm\n" + content + "\n"
      end
      @@music_content = entrytext unless entrytext == ''
    end
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
  # Github
  # ---------------------------
  def do_github
    if @config.key?(self.class.name)
        config = @config[self.class.name]
        if !config.key?('github_user') || config['github_user'] == ''
          @log.warn("Github user has not been configured or is invalid, please edit your slogger_config file.")
          return
        end
    else
      @log.warn("Github user has not been configured, please edit your slogger_config file.")
      return
    end
    @log.info("Logging Github activity for #{config['github_user']}")
    begin
      url = URI.parse "https://github.com/#{config['github_user'].strip}.json"

      http = Net::HTTP.new url.host, url.port
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.use_ssl = true

      res = nil

      http.start do |agent|
        res = agent.get(url.path).read_body
      end
    rescue Exception => e
      @log.error("ERROR retrieving Github url: #{url}")
      # p e
    end

    return false if res.nil?
    json = JSON.parse(res)

    output = ""
    entrytext = ""

    json.each {|action|
      date = Time.parse(action['created_at'])
      if date > @timespan
        case action['type']
          when "PushEvent"
            if !action["repository"]
              action['repository'] = {"name" => "unknown repository"}
            end
            output += "* Pushed to branch *#{action['payload']['ref'].gsub(/refs\/heads\//,'')}* of [#{action['repository']['name']}](#{action['url']})\n"
            action['payload']['shas'].each do |sha|
              output += "    * #{sha[2].gsub(/\n+/," ")}\n" unless sha.length < 3
            end
          when "GistEvent"
            output += "* Created gist [#{action['payload']['name']}](#{action['payload']['url']})\n"
            output += "    * #{action['payload']['desc'].gsub(/\n/," ")}\n" unless action['payload']['desc'].nil?
          when "WatchEvent"
            if action['payload']['action'] == "started"
              output += "* Started watching [#{action['repository']['owner']}/#{action['repository']['name']}](#{action['repository']['url']})\n"
              output += "    * #{action['repository']['description'].gsub(/\n/," ")}\n" unless action['repository']['description'].nil?
            end
        end
      else
        break
      end
    }

    return false if output.strip == ""
    if output != ''
      entrytext = "##### Github Activity\n" + output + "\n"
    end
    @@code_content += entrytext unless entrytext == ''
  end

  # ---------------------------
  # Gist
  # ---------------------------
  def do_gist
    if @config.key?(self.class.name)
        config = @config[self.class.name]
        if !config.key?('gist_user') || config['gist_user'] == ''
          @log.warn("RSS feeds have not been configured or a feed is invalid, please edit your slogger_config file.")
          return
        end
    else
      @log.warn("Gist user has not been configured, please edit your slogger_config file.")
      return
    end
    @log.info("Logging gists for #{config['gist_user']}")
    begin
      url = URI.parse "https://api.github.com/users/#{config['gist_user']}/gists"

      http = Net::HTTP.new url.host, url.port
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE
      http.use_ssl = true

      res = nil

      http.start do |agent|
        res = agent.get(url.path).read_body
      end
    rescue Exception => e
      raise "ERROR retrieving Gist url: #{url}"
      p e
    end
    # begin
    #   gist_url = URI.parse("https://api.github.com/users/#{@user}/gists")
    #   res = Net::HTTPS.get_response(gist_url).body

    return false if res.nil?
    json = JSON.parse(res)

    output = ""

    json.each {|gist|
      date = Time.parse(gist['created_at'])
      if date > @timespan
        output += "* Created [Gist ##{gist['id']}](#{gist["html_url"]})\n"
        output += "    * #{gist["description"]}\n" unless gist["description"].nil?
      else
        break
      end
    }

    return false if output.strip == ""
    entry = "## Gists for #{Time.now.strftime(@date_format)}:\n\n#{output}\n#{config['gist_tags']}"
    if output != ''
      entrytext = "##### Gists\n" + output + "\n"
    end
    @@code_content += entrytext unless entrytext == ''
  end

  # ---------------------------
  # Reading
  # ---------------------------
  def do_soundcloud
    if @config.key?(self.class.name)
      @scconfig = @config[self.class.name]
      if !@scconfig.key?('soundcloud_id') || @scconfig['soundcloud_id'] == [] || @scconfig['soundcloud_id'].nil?
        @log.warn("SoundCloud logging has not been configured or a feed is invalid, please edit your slogger_config file.")
        return
      else
        user = @scconfig['soundcloud_id']
      end
    else
      @log.warn("SoundCloud logging not been configured or a feed is invalid, please edit your slogger_config file.")
      return
    end
    @log.info("Logging SoundCloud uploads")

    retries = 0
    success = false

    until success
      if parse_soundcloud_feed("http://api.soundcloud.com/users/#{user}/tracks?limit=25&offset=0&linked_partitioning=1&secret_token=&client_id=ab472b80bdf8389dd6f607a10abfe33b&format=xml")
        success = true
      else
        break if $options[:max_retries] == retries
        retries += 1
        @log.error("Error parsing SoundCloud feed for user #{user}, retrying (#{retries}/#{$options[:max_retries]})")
        sleep 2
      end
    end

    unless success
      @log.fatal("Could not parse SoundCloud feed for user #{user}")
    end

  end

  def parse_soundcloud_feed(rss_feed)
    starred = @scconfig['soundcloud_starred'] || false

    begin
      rss_content = ""

      feed_download_response = Net::HTTP.get_response(URI.parse(rss_feed));
      xml_data = feed_download_response.body;

      doc = REXML::Document.new(xml_data);
      # Useful SoundCloud XML elements
      # created-at
      # permalink-url
      # artwork-url
      # title
      # description
      content = ''
      doc.root.each_element('//track') { |item|
        item_date = Time.parse(item.elements['created-at'].text)
        if item_date > @timespan
          content += "* [#{item.elements['title'].text}](#{item.elements['permalink-url'].text})\n" rescue ''
          desc = item.elements['description'].text
          content += "\n     #{desc}\n" unless desc.nil? or desc == ''
        else
          break
        end
      }
      unless content == ''
        @@music_content = "##### SoundCloud\n\n#{content}\n"
      end
    rescue Exception => e
      p e
      return false
    end
    return true
  end



  # ---------------------------
  # Reading
  # ---------------------------
  def do_reading
    content = ''

    do_instapaper

    if @@reading_content != ''
      content += "### Reading\n" + @@reading_content + "\n"
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
      content += "### Places\n" + @@place_content + "\n"
    end
    @@daily_content += content unless content == ''
  end

  # ---------------------------
  # Music
  # ---------------------------
  def do_music
    content = ''

    do_lastfm
    do_soundcloud

    if @@music_content != ''
      content += "### Music\n" + @@music_content + "\n"
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
      content += "### Bookmarks\n" + @@bookmark_content + "\n"
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
      content += "### Social\n" + @@social_content + "\n"
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
      content += "### Fitness\n" + @@fitness_content + "\n"
    end
    @@daily_content += content unless content == ''
  end

  # ---------------------------
  # Coding
  # ---------------------------
  def do_code
    content = ''

    do_github
    # do_gist

    if @@code_content != ''
      content += "### Code\n" + @@code_content + "\n"
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
    do_music
    do_reading
    do_bookmarks
    do_code

    options = {}

    if @@daily_content != ''
      @@daily_content = "# Daily Logs for #{Time.now.strftime(@date_format)}\n\n" + @@daily_content
      options['content'] = @@daily_content
      options['tags'] = ['daily logs']
      DayOne.new.to_dayone(options)
    end

  end
end
