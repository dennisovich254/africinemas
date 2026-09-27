"""Spikes S3 and S6 (plan P1.4): request hooks and token lifetime, on a real server.

Test-only app, served by s3_s6_real_server_tests.jac. `_before_request` is the
middleware hook the guides document (jac-sv-endpoints, jac-scale-http). If it ran, it
would append each request to the file named by S3_HOOK_LOG.
"""

import os;

walker _before_request {
    has request: dict[str, any] = {};

    can log with Root entry {
        with open(os.environ.get("S3_HOOK_LOG", "/dev/null"), "a") as f {
            f.write(f"{self.request}\n");
        }
    }
}

def:pub s3_hello -> str {
    return "hi";
}

walker:pub s3_ping {
    can go with Root entry {
        report "pong";
    }
}

def:priv s3_whoami -> str {
    return str(root.__jac__.id);
}
