# frozen_string_literal: true

css_path = ARGV.fetch(0, '_site/assets/css/jekyll-theme-chirpy.css')
css = File.read(css_path)

rules = css.scan(/([^{}]+)\{([^{}]*)\}/)

def final_main_background(rules, selector)
  rules.filter_map do |selectors, declarations|
    next unless selectors.split(',').map(&:strip).include?(selector)

    declarations[/--main-bg:\s*([^;]+)/i, 1]&.strip
  end.last
end

expected_backgrounds = {
  'html[data-mode=dark]' => '#000',
  ':root[data-bs-theme=dark]' => '#000',
  'html:not([data-mode]):not([data-bs-theme])' => '#000'
}

expected_backgrounds.each do |selector, expected|
  actual = final_main_background(rules, selector)
  next if actual&.casecmp?(expected)

  abort "Dark theme regression: #{selector} resolves --main-bg to #{actual || 'nothing'}, expected #{expected}"
end

puts 'Dark theme compatibility check passed'
