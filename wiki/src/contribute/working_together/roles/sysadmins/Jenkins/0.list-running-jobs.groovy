// List all "build_" jobs corresponding to currently queued and running builds.
//
// Use this before restarting Jenkins to get the list of jobs you should
// manually start once Jenkins is back up.
//
// This Groovy script can be run in the Jenkins Script Console, available at:
//
//     https://jenkins.tails.boum.org/script

queued = Hudson.instance.queue.items.collect() { it.getDisplayName() }
running = Jenkins.instance.getView('All').getBuilds().findAll() {
  it.getResult().equals(null);
}.collect() { it.getFullDisplayName() }

all = queued + running

unique = all.collect([] as HashSet) {
  it.replaceAll('^test_', 'build_')
          .replaceAll('^reproducibly_build_', 'build_')
          .replaceAll(' #.*$','');
}

unique.sort().each() { build ->
  println(build)
}

null
