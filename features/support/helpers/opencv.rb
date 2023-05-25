require 'English'
require 'open3'

class OpenCVInternalError < StandardError
end

module OpenCV
  def self.matchTemplate(image, screen, sensitivity, show_match)
    assert(sensitivity < 1.0)
    # Do a deep-copy so we don't mess up the outer environment
    env = Hash[ENV]
    if ENV['USER_DISPLAY'].nil? || ENV['USER_DISPLAY'] == ''
      show_match = false
    else
      env['DISPLAY'] = ENV['USER_DISPLAY']
    end
    # We will often kill the threads run by Open3 thanks to our
    # liberal use of try_for(), which raises an exception in those
    # threads. Since Ruby 2.5 those exceptions are reported to stderr
    # in the parent process, which will spam our log with useless
    # information, so we disable such reports temporarily.
    Thread.report_on_exception = false
    debug_log('OpenCV: starting opencv_match_template.py')
    stdout, stderr, p = Open3.capture3(
      env, 'python3', "#{GIT_DIR}/features/scripts/opencv_match_template.py",
      screen, image, sensitivity.to_s, show_match.to_s
    )
    case p.exitstatus
    when 0
      stdout.chomp.split.map(&:to_i)
    when 1
      nil
    else
      raise OpenCVInternalError, stderr
    end
  ensure
    Thread.report_on_exception = true
  end
end
