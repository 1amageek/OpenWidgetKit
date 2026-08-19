// FIXME(INCOMPLETE_IMPLEMENTATION): This target currently implements timeline value validation only.
// The production path uses this validation before scheduling, but registration, provider completion
// ownership, host updates, and shutdown are not implemented. Do not report the runtime as complete
// until those paths have explicit success, failure, ownership, and concurrency tests.

import OpenFoundation
