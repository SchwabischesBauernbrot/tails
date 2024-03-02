def boot_log
  $vm.execute_successfully('cat /var/log/boot.log').stdout
end

Then /^there is (a|no) random seed on USB drive "([^"]+)"$/ do |randomness, name|
  should_be_random = (randomness == 'a')
  path = $vm.storage.disk_path(name)

  # Store the old random seed for comparison
  if @random_seed
    if @old_random_seed && File.exist?(@old_random_seed)
      File.unlink(@old_random_seed)
    end
    @old_random_seed = @random_seed
    at_exit do
      File.unlink(@old_random_seed) if File.exist?(@old_random_seed)
    end
  end

  # Create an empty tempfile to store the random seed
  f = Tempfile.create('random-seed', $config['TMPDIR'])
  @random_seed = f.path
  at_exit do
    File.unlink(@random_seed) if File.exist?(@random_seed)
  end

  # Read the random seed from the USB drive
  cmd = "guestfish --ro -a #{path} run : pread-device /dev/sda 512 17408 \
         > #{@random_seed}"
  debug_log("Executing command: #{cmd}")
  p = IO.popen(cmd)
  Process.wait(p.pid)
  ret = $CHILD_STATUS
  assert_equal(0, ret, 'Failed to read the random seed from the USB drive')
  assert(File.exist?(@random_seed), 'Random seed file does not exist')
  assert(File.size(@random_seed).positive?, 'Random seed file is empty')

  # Check if the random seed is random
  cmd = "#{GIT_DIR}/features/scripts/check-randomness.py < #{@random_seed}"
  debug_log("Executing command: #{cmd}")
  p = IO.popen(cmd)
  out = p.readlines.join("\n")
  Process.wait(p.pid)
  ret = $CHILD_STATUS

  # Print the output for debugging purposes
  debug_log("Randomness check output: #{out}")

  if should_be_random
    assert_equal(0, ret, "Randomness check failed: #{out}")
  else
    assert_not_equal(0, ret, "Randomness check succeded but should have failed: #{out}")
  end
end

Then(/^the random seed is different from the previous one$/) do
  assert_not_nil(@old_random_seed, 'No previous random seed found')
  assert_not_nil(@random_seed, 'No random seed found')
  old_seed = File.open(@old_random_seed, 'rb', &:read)
  new_seed = File.open(@random_seed, 'rb', &:read)
  assert(old_seed != new_seed,
         "Random seed #{@random_seed} is the same as the previous one " \
         "(#{@old_random_seed})")
end

Then(/^the random seed was written multiple times on first boot$/) do
  log = boot_log
  assert_match(/First boot, writing random seed \d+ times/, log)
  assert_match(/Wrote random seed \d+ times/, log)
end
