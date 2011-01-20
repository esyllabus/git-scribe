require 'rubygems'
require 'nokogiri'
require 'liquid'

require 'fileutils'
require 'pp'

class GitScribe

  def initialize(args)
    @command = args.shift
    @args = args
  end

  def self.start(args)
    GitScribe.new(args).run
  end

  def run
    if @command && self.respond_to?(@command)
      self.send @command
    else
      help
    end
  end

  ## COMMANDS ##
 
  def help
    puts "No command: #{@command}"
    puts "TODO: tons of help"
  end

  # start a new scribe directory with skeleton structure
  def init
  end

  # check that we have everything needed
  def check
    # look for a2x (asciidoc, latex, xsltproc)
  end

  BOOK_FILE = 'book.asc'

  OUTPUT_TYPES = ['pdf', 'epub', 'mobi', 'html', 'site']

  # generate the new media
  def gen
    type = @args.shift || 'all'
    prepare_output_dir

    gather_and_process

    types = type == 'all' ? OUTPUT_TYPES : [type]

    output = []
    Dir.chdir("output") do
      types.each do |out_type|
        call = 'do_' + out_type
        if self.respond_to? call
          self.send call
        else
          puts "NOT A THING: #{call}"
        end
      end
      # clean up
      # `rm #{BOOK_FILE}`
      # TODO: open media (?)
    end
  end

  def prepare_output_dir
    Dir.mkdir('output') rescue nil
    Dir.chdir('output') do
      Dir.mkdir('stylesheets') rescue nil
      from_stdir = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'stylesheets'))
      FileUtils.cp_r from_stdir, '.'
    end
  end

  def a2x(type)
    "a2x -f #{type} -d book -r resources"
  end

  def a2x_wss(type)
    a2x(type) + " --stylesheet=stylesheets/handbookish.css"
  end

  def do_pdf
    puts "GENERATING PDF"
    # TODO: syntax highlighting (fop?)
    `#{a2x('pdf')} --dblatex-opts "-P latex.output.revhistory=0" #{BOOK_FILE}`
    if $?.exitstatus == 0
      'book.pdf'
    end
  end

  def do_epub
    puts "GENERATING EPUB"
    # TODO: look for custom stylesheets
    `#{a2x_wss('epub')} --epubcheck #{BOOK_FILE}`
    puts 'exit status', $?.exitstatus
    'book.epub'
  end

  def do_html
    puts "GENERATING HTML"
    # TODO: look for custom stylesheets
    #puts `#{a2x_wss('xhtml')} -v #{BOOK_FILE}`
    styledir = File.expand_path(File.join(Dir.pwd, 'stylesheets'))
    puts cmd = "asciidoc -a stylesdir=#{styledir} -a theme=handbookish #{BOOK_FILE}"
    `#{cmd}`
    puts 'exit status', $?.exitstatus
    'book.html'
  end

  def do_site
    puts "GENERATING SITE"
    # TODO: check if html was already done
    puts `asciidoc -b docbook #{BOOK_FILE}`
    xsldir = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'docbook-xsl', 'xhtml'))
    `xsltproc --stringparam html.stylesheet stylesheets/handbookish.css --nonet #{xsldir}/chunk.xsl book.xml`

    source = File.read('index.html')
    html = Nokogiri::XML.parse(source)

    sections = []
    c = -1

    # each chapter
    html.css('.toc > dl').each do |section|
      section.children.each do |item|
        if item.name == 'dt' # section
          c += 1
          sections[c] ||= {}
          link = item.css('a').first
          sections[c]['title'] = title = link.text
          sections[c]['href'] = href = link['href']
          clean_title = title.downcase.gsub(/[^a-z0-9\-_]+/, '_') + '.html'
          sections[c]['link'] = clean_title
          if href[0, 10] == 'index.html'
            sections[c]['link'] = 'title.html'
          end
          sections[c]['sub'] = []
        end
        if item.name == 'dd' # subsection
          item.css('dt').each do |sub|
            link = item.css('a').first
            data = {}
            data['title'] = title = link.text
            data['href'] = href = link['href']
            data['link'] = sections[c]['link'] + '#' + href.split('#').last
            sections[c]['sub'] << data
          end
        end
      end
      puts
    end

    book_title = html.css('head > title').text
    content = html.css('div.section').first.to_html
    header = html.css('div.navheader').to_html
    footer = html.css('div.navfooter').to_html

    template_dir = File.expand_path(File.join(File.dirname(__FILE__), '..', '..', 'site', 'default'))
    Liquid::Template.file_system = Liquid::LocalFileSystem.new(template_dir)
    index_template = Liquid::Template.parse(File.read(File.join(template_dir, 'index.html')))
    page_template = Liquid::Template.parse(File.read(File.join(template_dir, 'page.html')))

    # write the index page
    File.open('index.html', 'w+') do |f|
      data = { 
        'title' => book_title,
        'sections' => sections
      }
      f.puts index_template.render( data )
    end

    # write the title page
    File.open('title.html', 'w+') do |f|
      data = { 
        'title' => sections.first['title'],
        'sub' => sections.first['sub'],
        'prev' => {'link' => 'index.html', 'title' => "Main"},
        'home' => {'link' => 'index.html', 'title' => "Home"},
        'next' => sections[1],
        'content' => content
      }
      f.puts page_template.render( data )
    end

    # write the other pages
    sections.each_with_index do |section, i|

      if i > 0 # skip title page
        source = File.read(section['href'])
        puts source

        html = Nokogiri::XML.parse(source)

        content = html.css('div.section').first.to_html

        File.open(section['link'], 'w+') do |f|
          next_section = nil
          if i <= sections.size
            next_section = sections[i+1]
          end
          data = { 
            'title' => section['title'],
            'sub' => section['sub'],
            'prev' => sections[i-1],
            'home' => {'link' => 'index.html', 'title' => "Home"},
            'next' => next_section,
            'content' => content
          }
          f.puts page_template.render( data )
        end
        File.unlink(section['href'])

        puts i
        puts section['title']
        puts section['href']
        puts section['link']
        puts
      end

      #File.unlink
    end
  end


  # create a new file by concatenating all the ones we find
  def gather_and_process
    files = Dir.glob("book/*")
    FileUtils.cp_r files, 'output'
  end

  # DISPLAY HELPER FUNCTIONS #

  def l(info, size)
    clean(info)[0, size].ljust(size)
  end

  def r(info, size)
    clean(info)[0, size].rjust(size)
  end

  def clean(info)
    info.to_s.gsub("\n", ' ')
  end

  # API/DATA HELPER FUNCTIONS #

  def git(command)
    `git #{command}`.chomp
  end
end
