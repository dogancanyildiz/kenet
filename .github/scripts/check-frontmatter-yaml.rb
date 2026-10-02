#!/usr/bin/env ruby
# frozen_string_literal: true

# Frontmatter fixture'larını başka YAML okuyucularına gösteren geliştirici betiği.
#
# Core'un okuyucusu ve yazıcısı aynı kuralları paylaşır; ikisinde birden yanlış olan bir kural
# kendi testlerinden geçer. Bu betik aynı dosyaları bağımsız okuyuculara verir:
#   - Ruby Psych (libyaml, YAML 1.1): her zaman.
#   - js-yaml (YAML 1.2, Obsidian'ın okuyucusu): JS_YAML ortam değişkeni js-yaml modül
#     klasörünü gösteriyorsa ve `node` kuruluysa.
#
# CI'da çalışmaz; frontmatter kuralları ya da fixture'lar değiştiğinde elle çalıştırılır.
#
#   ruby .github/scripts/check-frontmatter-yaml.rb
#   JS_YAML=/yol/node_modules/js-yaml ruby .github/scripts/check-frontmatter-yaml.rb
#
# Denetlenenler:
#   - Fixtures/parse: `parsed` beklenen her bloğu okuyucu da kabul etmeli ve aynı değerleri
#     vermeli. `unreadable` beklenen blokta okuyucunun kabul etmesi hata değildir (uygulama
#     bilerek daha katıdır); bilgi olarak listelenir.
#   - Fixtures/write: her `expected.md` bloğu okunabilmeli ve işlemin yazdığı değer okuyucuda
#     da aynı değer olmalı.
#
# Beklenen farklar: uygulamanın bilerek metin okuduğu yazımlar (`yes`, `012`, `0x1F`, `.5`,
# `14:30`, üstel sayılar, `2026-1-2`, zaman damgaları). Bunlar ayrı sayılır ve hata değildir.
#
# Rastgele örneklem: testler FRONTMATTER_SAMPLES_DIR ile çalıştırılınca uygulamanın okuduğu
# her bloğu o klasöre yazar; aynı klasör bu betiğe verilince okuyucuların reddettiği bloklar
# listelenir (hiç olmamalı):
#
#   FRONTMATTER_SAMPLES_DIR=/tmp/ornekler swift test --package-path Packages/Core
#   ruby .github/scripts/check-frontmatter-yaml.rb --samples /tmp/ornekler

require 'yaml'
require 'json'
require 'date'
require 'open3'

ROOT = File.expand_path('../../Fixtures', __dir__)

# Uygulamanın metin okuduğu, başka okuyucuların başka türe çevirebildiği yazımlar.
EXPECTED_TEXT = [
  /\A(yes|no|on|off|y|n)\z/i,                       # YAML 1.1 evet/hayır sözcükleri
  /\A[-+]?0[0-9_]+\z/, /\A[-+]?0[xob][0-9a-f_]+\z/i, # baştaki sıfır, on altılık, sekizlik, ikilik
  /\A[-+]?(\.[0-9]+|[0-9]+\.)\z/,                   # .5 ve 5.
  /\A[-+]?[0-9]+(:[0-9]+)+\z/,                      # 14:30 (altmışlık)
  /\A[-+]?[0-9.]+e[-+]?[0-9]+\z/i,                  # üstel sayı
  /\A[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}([Tt ].*)?\z/,   # kısa tarih ve zaman damgası
  /\A:/                                             # Psych: Ruby simgesi
].freeze

# Okuyucunun verdiği değeri karşılaştırılabilir düz bir biçime çevirir.
def normalize(value)
  case value
  when Hash then value.map { |key, item| [key.is_a?(String) ? key : key.inspect, normalize(item)] }.to_h
  when Array then value.map { |item| normalize(item) }
  when Date then ['date', value.strftime('%Y-%m-%d')]
  when Time then ['time', value.utc.strftime('%Y-%m-%dT%H:%M:%SZ')]
  when Symbol then ['symbol', value.to_s]
  else value
  end
end

def psych_load(text)
  value = begin
    YAML.safe_load(text, permitted_classes: [Date, Time, Symbol], aliases: true)
  rescue ArgumentError
    YAML.safe_load(text, [Date, Time, Symbol], [], true)
  end
  { 'ok' => true, 'value' => normalize(value) }
rescue Psych::Exception => e
  { 'ok' => false, 'error' => e.message.lines.first.to_s.strip }
end

JS_LOADER = <<~JAVASCRIPT
  const yaml = require(process.argv[1]);
  const blocks = JSON.parse(require('fs').readFileSync(0, 'utf8'));
  const normalize = (value) => {
    if (value instanceof Date) {
      const iso = value.toISOString();
      return iso.endsWith('T00:00:00.000Z') ? ['date', iso.slice(0, 10)] : ['time', iso];
    }
    if (Array.isArray(value)) return value.map(normalize);
    if (value && typeof value === 'object') {
      return Object.fromEntries(Object.entries(value).map(([key, item]) => [key, normalize(item)]));
    }
    return value === undefined ? null : value;
  };
  const results = blocks.map((text) => {
    try {
      return { ok: true, value: normalize(yaml.load(text)) };
    } catch (error) {
      return { ok: false, error: String(error.message).split('\\n')[0] };
    }
  });
  process.stdout.write(JSON.stringify(results));
JAVASCRIPT

# Okuyucu adı => blok listesini sonuç listesine çeviren işlev.
def readers
  list = { 'Psych' => ->(blocks) { blocks.map { |text| psych_load(text) } } }
  module_path = ENV['JS_YAML']
  if module_path && !module_path.empty?
    list['js-yaml'] = lambda do |blocks|
      output, status = Open3.capture2('node', '-e', JS_LOADER, module_path, stdin_data: JSON.generate(blocks))
      abort 'js-yaml çalıştırılamadı (node ve JS_YAML yolunu denetleyin).' unless status.success?
      JSON.parse(output)
    end
  end
  list
end

# Dosyanın frontmatter bloğu (sınır satırları arasındaki satırlar, LF ile). Blok yoksa ya da
# UTF-8 değilse nil.
def block_of(path)
  bytes = File.binread(path)
  bytes = bytes.byteslice(3..-1) if bytes.start_with?("\xEF\xBB\xBF".b)
  lines = bytes.split(/\r\n|\r|\n/n, -1)
  return nil unless lines.first == '---'

  closing = lines[1..-1].index('---')
  return nil unless closing

  block = lines[1, closing].map { |line| "#{line}\n" }.join.force_encoding('UTF-8')
  block.valid_encoding? ? block : nil
end

def expected_difference?(text)
  EXPECTED_TEXT.any? { |pattern| pattern.match?(text) }
end

# Beklenen tek değer ile okuyucunun değerini karşılaştırır: :same, :expected ya da :different.
def compare(type, text, actual)
  same =
    case type
    when 'text' then actual.is_a?(String) && actual == text
    when 'number' then actual.is_a?(Numeric) && actual.to_f == Float(text)
    when 'boolean' then actual == (text.casecmp('true').zero?)
    when 'date' then actual == ['date', text]
    when 'empty' then actual.nil?
    end
  return :same if same

  type == 'text' && expected_difference?(text) ? :expected : :different
end

class Report
  attr_reader :failures

  def initialize
    @failures = []
    @expected = []
    @stricter = []
    @checked = 0
  end

  def check(reader, where, type, text, actual)
    @checked += 1
    case compare(type, text, actual)
    when :expected then @expected << "#{reader}: #{where}: #{text.inspect} => #{actual.inspect}"
    when :different then fail!(reader, where, "#{type} #{text.inspect} beklenirken #{actual.inspect}")
    end
  end

  def fail!(reader, where, message)
    @failures << "#{reader}: #{where}: #{message}"
  end

  def stricter(reader, where)
    @stricter << "#{reader}: #{where}"
  end

  # `limit` verilirse her listeden en çok o kadar satır yazılır.
  def print(limit: nil)
    puts "Karşılaştırılan değer: #{@checked}"
    list('Beklenen fark (bilerek metin okunan yazımlar)', @expected, limit)
    list('Uygulamanın çözülemez saydığı, okuyucunun kabul ettiği blok', @stricter, limit)
    list('Beklenmeyen fark', @failures, limit)
  end

  private

  def list(title, lines, limit)
    puts "#{title}: #{lines.size}"
    (limit ? lines.first(limit) : lines).each { |line| puts "  #{line}" }
  end
end

def check_field(report, reader, where, field, actual)
  if field['scalar']
    report.check(reader, where, field['scalar']['type'], field['scalar']['text'], actual)
  elsif field['list']
    items = field['list']['items']
    return report.fail!(reader, where, "liste beklenirken #{actual.inspect}") unless actual.is_a?(Array) && actual.size == items.size

    items.each_with_index { |item, index| report.check(reader, "#{where}[#{index}]", item['type'], item['text'], actual[index]) }
  elsif field['mapping']
    entries = field['mapping']
    # js-yaml sayıya benzeyen anahtarları öne aldığı için sıra karşılaştırılmaz.
    return report.fail!(reader, where, "eşlem beklenirken #{actual.inspect}") unless actual.is_a?(Hash) && actual.keys.sort == entries.map { |entry| entry['key'] }.sort

    entries.each { |entry| report.check(reader, "#{where}.#{entry['key']}", entry['value']['type'], entry['value']['text'], actual[entry['key']]) }
  end
end

def check_parse(report, reader, name, expected, result)
  case expected['state']
  when 'unreadable'
    report.stricter(reader, "parse/#{name}") if result['ok']
  when 'parsed'
    return report.fail!(reader, "parse/#{name}", "okuyucu reddetti: #{result['error']}") unless result['ok']

    value = result['value'] || {}
    fields = expected['fields']
    unless value.is_a?(Hash) && value.size == fields.size
      return report.fail!(reader, "parse/#{name}", "alanlar farklı: #{value.is_a?(Hash) ? value.keys.inspect : value.inspect}")
    end

    # Aynı adlı anahtarlar eşleşir. Kalanlar sırayla eşlenir: `no` gibi bir anahtarı YAML 1.1
    # başka türe çevirir. (js-yaml sayıya benzeyen anahtarları öne aldığı için sıra kullanılmaz.)
    unmatched = value.keys - fields.map { |field| field['key'] }
    fields.each do |field|
      key = field['key']
      unless value.key?(key)
        key = unmatched.shift
        report.check(reader, "parse/#{name}: anahtar", 'text', field['key'], key)
      end
      check_field(report, reader, "parse/#{name}: #{field['key']}", field, value[key])
    end
  end
end

# `operation.json` içindeki değeri fixture türüne ve metnine çevirir.
def literal(value)
  type, content = value.first
  case type
  when 'text' then ['text', content]
  when 'boolean' then ['boolean', content.to_s]
  when 'integer', 'number' then ['number', content.to_s]
  when 'date' then ['date', content]
  end
end

def check_write(report, reader, name, operation, result)
  where = "write/#{name}"
  return report.fail!(reader, where, "okuyucu reddetti: #{result['error']}") unless result['ok']

  value = result['value'] || {}
  return report.fail!(reader, where, "eşlem beklenirken #{value.inspect}") unless value.is_a?(Hash)

  target = value[operation['key']]
  case operation['operation']
  when 'set-value'
    report.check(reader, where, *literal(operation['value']), target)
  when 'set-list'
    items = target.nil? ? [] : Array(target)
    return report.fail!(reader, where, "#{operation['items'].size} öğe beklenirken #{target.inspect}") unless items.size == operation['items'].size

    operation['items'].each_with_index { |item, index| report.check(reader, "#{where}[#{index}]", *literal(item), items[index]) }
  when 'set-entry'
    return report.fail!(reader, where, "eşlem beklenirken #{target.inspect}") unless target.is_a?(Hash)

    report.check(reader, where, *literal(operation['value']), target[operation['entry']])
  when 'remove-entry'
    report.fail!(reader, where, 'kayıt hâlâ duruyor') if target.is_a?(Hash) && target.key?(operation['entry'])
  when 'remove-field'
    report.fail!(reader, where, 'alan hâlâ duruyor') if value.key?(operation['key'])
  end
end

def check_fixtures
  report = Report.new
  parse_cases = Dir.children(File.join(ROOT, 'parse')).sort.map do |name|
    expected = JSON.parse(File.read(File.join(ROOT, 'parse', name, 'expected.json')))['frontmatter']
    [name, expected, block_of(File.join(ROOT, 'parse', name, 'input.md'))]
  end.select { |_, expected, block| expected && expected['state'] != 'absent' && block }
  write_cases = Dir.children(File.join(ROOT, 'write')).sort.map do |name|
    description = JSON.parse(File.read(File.join(ROOT, 'write', name, 'operation.json')))
    expected_path = File.join(ROOT, 'write', name, 'expected.md')
    [name, description['frontmatter'], File.exist?(expected_path) ? block_of(expected_path) : nil]
  end.select { |_, operation, block| operation && block }

  readers.each do |reader, load|
    parse_results = load.call(parse_cases.map { |_, _, block| block })
    parse_cases.each_with_index { |(name, expected, _), index| check_parse(report, reader, name, expected, parse_results[index]) }
    write_results = load.call(write_cases.map { |_, _, block| block })
    write_cases.each_with_index { |(name, operation, _), index| check_write(report, reader, name, operation, write_results[index]) }
    puts "#{reader}: #{parse_cases.size} okuma, #{write_cases.size} yazma örneği"
  end
  report.print
  exit(report.failures.empty? ? 0 : 1)
end

def check_samples(directory)
  paths = Dir.glob(File.join(directory, '*.yaml')).sort
  blocks = paths.map { |path| File.read(path, encoding: 'UTF-8') }
  expectations = paths.map do |path|
    json = path.sub(/\.yaml\z/, '.json')
    File.exist?(json) ? JSON.parse(File.read(json, encoding: 'UTF-8'))['frontmatter'] : nil
  end
  report = Report.new
  rejected = 0
  readers.each do |reader, load|
    results = load.call(blocks)
    refused = results.each_index.reject { |index| results[index]['ok'] }
    rejected += refused.size
    puts "#{reader}: #{blocks.size} bloktan #{refused.size} tanesi reddedildi"
    # Aynı nedenle reddedilenler birlikte, en kısa örnekle gösterilir.
    groups = refused.group_by { |index| results[index]['error'].gsub(/\d+/, 'N') }
    groups.each do |error, indexes|
      example = indexes.min_by { |index| blocks[index].size }
      puts "  #{indexes.size} blok: #{error}\n    #{File.basename(paths[example])}\n#{blocks[example].gsub(/^/, '    | ')}"
    end
    # Kabul edilen bloklarda değerler de uygulamanın okuduğuyla aynı olmalı.
    results.each_with_index do |result, index|
      next unless result['ok'] && expectations[index]

      # Blok satır sonları LF'ye çevrilerek yazıldığı için satır numaraları karşılaştırılmaz.
      check_parse(report, reader, File.basename(paths[index], '.yaml'), expectations[index], result)
    end
  end
  report.print(limit: 20)
  exit(rejected.zero? && report.failures.empty? ? 0 : 1)
end

if ARGV.first == '--samples'
  abort 'Kullanım: check-frontmatter-yaml.rb --samples KLASÖR' unless ARGV[1] && Dir.exist?(ARGV[1])
  check_samples(ARGV[1])
else
  check_fixtures
end
