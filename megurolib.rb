require File.expand_path('../base.rb', __FILE__)

class MeguroLib < Base
  self.url = 'http://www.meguro-library.jp/'

  def search(str)
    s.visit MeguroLib.url
    s.fill_in :"text(1)", with: str
    s.find(:css, '#doSearch').click

    return Result.new(s)
  end

  # 借りている資料
  def borrowing
    login
    borrowing_table.rows.map do |row|
      cells = row.cells.map(&:text)
      Book::Borrowing.new(*splite_title(cells[2]), due: cells[6])
    end
  end

  # 予約している資料
  def reserving
    login
    reserving_table.rows.map do |row|
      cells = row.cells.map(&:text)
      Book::Reserving.new(*splite_title(cells[2]), status: cells[4], reserved_until: cells[5])
    end
  end

  def login
    top
    s.find(:xpath, '//*[@id="km_user_widget-2"]/div/a[2]/img').click
    s.fill_in :usercardno, with: conf['card']
    s.fill_in :userpasswd, with: conf['password']
    s.find(:xpath, '//table[4]//tr[2]/td[1]/table//tr[3]/td/input[1]').click
    delay
    login_successful?
  end

  # TODO: sessionまわりを整頓して連続予約
  # TODO: シリーズ予約に対応
  def reserve(sess, book)
    cd sess
    puts "reserve: #{book.title} (#{book.publisher})"

    target_link = s.all(:xpath, '//table[7]/tbody/tr').drop(1).map do |row|
      if row.find(:css, 'td:nth-child(2)').text.include?(book.title) &&
          row.find(:css, 'td:nth-child(4)').text.include?(book.publisher)
        row.find(:css, 'a')
      end
    end.find{|a| !a.nil? }
    target_link.click
    delay
    s.click_link '予約の候補にする'
    delay
    s.fill_in :usercardid, with: conf['card']
    s.fill_in :password, with: conf['password']
    s.select '3', from: 'library' # 中目黒駅前図書館
    s.click_button '登録する'
    delay
    s.click_button '予約する'
  end

  private def login_successful?
            contains_text? 'メールアドレスの確認・変更・削除'
          end

  private def borrowing_table
    scrape_table('//form[1]/table[2]')
  end

  private def reserving_table
    scrape_table('//form[2]/table[2]')
  end

  private def splite_title(title_with_publisher)
    return [title_with_publisher, ''] unless title_with_publisher.index('／')
    title_with_publisher.split('／').map(&:strip)
  end

  class Book
    attr_accessor :title, :author, :publisher, :published_at

    def initialize(title, author: nil, publisher: nil, published_at: nil)
      @title         = title

      # result list page
      @author        = author
      @publisher     = publisher
      @published_at  = Time.new(published_at.gsub('.', '/')) if published_at
    end

    class Borrowing < self
      attr_reader :due

      def initialize(title, publisher, due: nil)
        super(title, publisher: publisher)
        @due = Time.parse(due + ' 23:59:59') if due
      end
    end

    class Reserving < self
      attr_reader :status, :reserved_until

      def initialize(title, publisher, status: , reserved_until: nil)
        super(title, publisher: publisher)
        @status = status
        @reserved_until = Time.parse(reserved_until + ' 23:59:59') if reserved_until.present?
      end
    end
  end

  class Result
    attr_reader :session, :count, :books

    def initialize(session)
      @session = session.dup
      @count = session.find(:xpath, '//table[4]//tr/td[1]').text.scan(/\d+/).first.to_i

      # contains books only in first page.
      rows = session.all(:xpath, '//table[7]//tr[td]')
      @books = rows.map do |row|
        tds = row.all(:xpath, 'td')
        Book.new(tds[1].text.split('[').first.strip,
                 author: tds[2].text,
                 publisher: tds[3].text,
                 published_at: tds[4].text)
      end
    end
  end
end
