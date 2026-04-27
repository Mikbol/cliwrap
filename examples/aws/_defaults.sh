# @match *
# @mode  pre
# @desc  Apply sensible defaults to every aws invocation

run() {
  export AWS_REGION="${AWS_REGION:-eu-north-1}"
  export AWS_PAGER=""   # disable the annoying less pager
}
