check: $(BUILT_SOURCES)
	if test -n "$$FOLKS_TEST_VALGRIND"; then \
		G_DEBUG=${G_DEBUG:+"${G_DEBUG},"}gc-friendly; \
		G_SLICE=${G_SLICE},always-malloc; \
		$(MAKE) $(AM_MAKEFLAGS) \
			TESTS_ENVIRONMENT="$(TESTS_ENVIRONMENT) \
			libtool --mode=execute valgrind \
					--leak-check=full \
					--show-reachable=no \
					--gen-suppressions=all \
					--num-callers=20 \
					--error-exitcode=0 \
					--log-file=valgrind.log.%p" \
			check-am; \
	else \
		$(MAKE) $(AM_MAKEFLAGS) check-am; \
	fi

