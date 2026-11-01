// Lab 8: jenkins-pr-checks-security-gates
// Multibranch pipeline: every pull request (and main) runs five gates in parallel and reports
// each one to GitHub as its own commit status. Branch protection on main requires all five,
// so a pull request cannot be merged until every gate passes.
//
//   ci/tests         flake8, unit tests, coverage >= 90%
//   ci/secrets       gitleaks over the whole git history
//   ci/sast          bandit static analysis (medium+ severity and confidence)
//   ci/dependencies  Trivy: HIGH/CRITICAL vulnerabilities with a fix available
//   ci/dockerfile    hadolint, warnings and above
//
// Each gate runs in a throwaway container that receives a COPY of the workspace
// (ci/in-container.sh): pull request code never sees JENKINS_HOME or its credentials.

@Library('ci-labs@v1.0.0') _

// Report one status to GitHub (githubNotify: plugin "Pipeline: GitHub Notify Step").
// A reporting error is logged, not fatal: a missing required status still blocks the
// merge, so this fails safe. Throwable also covers a missing plugin (NoSuchMethodError).
def notify(String context, String state, String description) {
  try {
    githubNotify(context: context, status: state, description: description, sha: env.GIT_COMMIT)
  } catch (Throwable err) {
    echo "WARNING: could not report ${context}=${state} to GitHub: ${err.message}"
  }
}

// Run one gate and report its outcome under its own status context.
def gate(String context, String what, Closure body) {
  notify(context, 'PENDING', "${what}: running")
  try {
    body()
    notify(context, 'SUCCESS', "${what}: passed")
  } catch (err) {
    notify(context, 'FAILURE', "${what}: failed, see Jenkins")
    throw err
  }
}

pipeline {
  agent any

  options {
    disableConcurrentBuilds(abortPrevious: true)   // a new push to a PR cancels the old run
    buildDiscarder(logRotator(numToKeepStr: '20'))
    timeout(time: 20, unit: 'MINUTES')
  }

  environment {
    PY_IMAGE       = 'python:3.11-slim'
    GITLEAKS_IMAGE = 'zricethezav/gitleaks:v8.21.2'
    TRIVY_IMAGE    = 'aquasec/trivy:0.56.2'
    HADOLINT_IMAGE = 'hadolint/hadolint:v2.12.0'
    PIP_FLAGS      = '-q --disable-pip-version-check --root-user-action=ignore'
  }

  stages {
    stage('Preflight') {
      steps {
        script {
          labPreflight(docker: true)
          String what = env.CHANGE_ID ? "PR #${env.CHANGE_ID}: ${env.CHANGE_BRANCH} -> ${env.CHANGE_TARGET}"
                                      : "branch ${env.BRANCH_NAME}"
          currentBuild.description = what
          echo "checking ${what} at ${env.GIT_COMMIT}"
          for (String c : ['ci/tests', 'ci/secrets', 'ci/sast', 'ci/dependencies', 'ci/dockerfile']) {
            notify(c, 'PENDING', 'queued')
          }
          sh 'rm -rf reports && mkdir -p reports'
        }
      }
    }

    stage('Gates') {
      parallel {
        stage('Tests') {
          steps {
            script {
              gate('ci/tests', 'Lint, tests, coverage >= 90%') {
                sh '''
                  bash ci/in-container.sh "$PY_IMAGE" -- sh -c "pip install $PIP_FLAGS -r app/requirements-dev.txt && cd app && flake8 && python -m pytest -q -p no:cacheprovider --junitxml=/src/reports/junit.xml --cov=app --cov-report=term-missing --cov-fail-under=90"
                '''
              }
            }
          }
          post {
            always {
              junit(testResults: 'reports/junit.xml', allowEmptyResults: true)
            }
          }
        }

        stage('Secrets') {
          steps {
            script {
              gate('ci/secrets', 'Secret scan (gitleaks)') {
                sh '''
                  bash ci/in-container.sh "$GITLEAKS_IMAGE" -- git --redact -v --exit-code 1 --report-format sarif --report-path /src/reports/gitleaks.sarif /src
                '''
              }
            }
          }
        }

        stage('SAST') {
          steps {
            script {
              gate('ci/sast', 'Static analysis (bandit)') {
                sh '''
                  bash ci/in-container.sh "$PY_IMAGE" -- sh -c "pip install $PIP_FLAGS bandit==1.7.10 && bandit -r app -x app/tests -ll -ii"
                '''
              }
            }
          }
        }

        stage('Dependencies') {
          steps {
            script {
              gate('ci/dependencies', 'Dependency CVEs (Trivy)') {
                // The vulnerability database is cached in a named volume, not in JENKINS_HOME
                sh '''
                  bash ci/in-container.sh "$TRIVY_IMAGE" -v ci-labs-trivy-cache:/root/.cache/trivy -- fs --scanners vuln --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 --no-progress /src/app
                '''
              }
            }
          }
        }

        stage('Dockerfile') {
          steps {
            script {
              gate('ci/dockerfile', 'Dockerfile lint (hadolint)') {
                sh '''
                  bash ci/in-container.sh "$HADOLINT_IMAGE" --entrypoint /bin/hadolint -- --failure-threshold warning /src/Dockerfile
                '''
              }
            }
          }
        }
      }
    }
  }

  post {
    always {
      archiveArtifacts(artifacts: 'reports/**', allowEmptyArchive: true)
    }
    failure {
      echo 'At least one gate failed: GitHub will not allow this pull request to be merged until it passes.'
    }
  }
}
