#!/usr/bin/env ruby
require 'socket'
require 'cgi'
require 'open-uri'
require 'rexml/document'
require 'builder'
require 'zlib'
include REXML

class IRC
  def initialize(server, port, nick, chan, builder)
        @@started = nil
        @queue = Array.new
        @x = builder

        @nick   = nick
        @chan   = chan
        @server = server
        @port   = port
        @edit_count = 0
        @edits = {}
  end

  def connect
        @irc = TCPSocket.open(@server, @port)
        send("USER " + (@nick + " ") * 3 + " :" + (@nick + " ") * 2)
        send("NICK " + @nick)
        send("JOIN " + @chan)
  end

  def loop
        for x in @irc
          parse(x)
        end
        connect()
        loop()
  end

  def parse(line)
        case line
          when /Closing Link/ then reconnect()
          when /^PING (.+)[\r\n]{1,2}?/ then send("PONG #{$1}");
          when /KICK (#.+)/ then send("JOIN #{$1}")
          when /^:(.+)\!.+\@.+ PRIVMSG (\#.+) :(.+)/ then parse_msg($1, $2, $3)
          else
            print line
      end
  end

  def parse_msg(user, chan, message)
    if chan == @chan && user == 'rc' && message =~ /http:\/\/([^\.]+)\.wikipedia\.org\/w\/index\.php\?title=([^&]*)&diff=(\d+)&oldid=(\d+)/
      lang = $1
      title = $2
      new_id = $3
      old_id = $4
      p [@edit_count, lang, CGI::unescape(title).gsub(/_/, ' '), new_id, old_id] if (@edit_count += 1) % 1000 == 0
      add_edit(lang, new_id) 
    end
  end

  def reconnect
        connect(@server, @port, @nick, @chan)
        loop()
  end

  def add_edit(language, id)
    list = (@edits[language] ||= [])
    list << id
    if list.length % 10 == 0
      url = "http://#{language}.wikipedia.org/w/api.php?format=xml&action=query&prop=revisions&revids=#{CGI::escape(list.join('|'))}&rvprop=#{CGI::escape('revid|timestamp|user|comment|content|flags')}"
      contents = Document.new(open(url) { |file| file.read })
      index = 0
      contents.elements.each("//page") do |page|
        ns = page.attributes["ns"]
        title = page.attributes["title"]
        page_id = page.attributes["pageid"]
        revision = page.get_elements("revisions/rev").first
        revid = revision.attributes["revid"]
        timestamp = revision.attributes["timestamp"]
        user = revision.attributes["user"]
        comment = revision.attributes["comment"]
        content = revision.texts.join
        minor = revision.attributes["flags"]
        @x.page { 
          @x.title(title)
          @x.id(page_id)
          @x.revision {
            @x.id(list[index])
            @x.timestamp(timestamp)
            @x.constributer {
              @x.username(user)
              #x.id("NOTKNOWN")
            }
            @x.minor(minor) if minor
            @x.text(content )
          }
        }
        index += 1
      end
      list.clear
    end
  end

  def send(input)
        puts input if $debug
         # If * seconds have passed since last message
         # _not_ implemented properly yet
        @queue.push(input)

        @irc.send(@queue[-1] + "\r\n", 0)
        @queue.delete_at(-1)
  end
end

nick = "YOURNICK"
chan = "#en.wikipedia"
server = "irc.wikimedia.org"
port = 6667

$log = Zlib::GzipWriter.open("out.xml.gz")
$log.puts "<mediawiki>"

trap "SIGINT", proc{ $log.puts("</mediawiki>"); $log.close; exit }
builder = Builder::XmlMarkup.new(:target => $log, :indent => 1)
builder.instruct!
irc = IRC.new(server, port, nick, chan, builder)
irc.connect
irc.loop
