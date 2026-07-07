#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT=/home/dylee3/Documents/MDrive
RESULTS_TAG=${RESULTS_TAG:-v2xpnp_noinfra_yhs_5}
ROUTES_DIR=${ROUTES_DIR:-scenarioset/v2xpnp}
PLANNER=${PLANNER:-codriving_yhs}
GPU=${CUDA_VISIBLE_DEVICES:-0}
PORT=${PORT:-2014}
TM_PORT=${TM_PORT:-2019}
TIMEOUT=${TIMEOUT:-600}
RETRY_LIMIT=${RETRY_LIMIT:-4}

PYTHON=${PYTHON:-/home/dylee3/anaconda3/envs/tcp_codriving/bin/python}
CARLA_ROOT=${CARLA_ROOT:-/home/dylee3/Documents/MDrive/carla912}
LOG_DIR=${LOG_DIR:-$REPO_ROOT/logs/full_eval}
RUN_LOG=$LOG_DIR/isolated_runner_${RESULTS_TAG}_${PLANNER}.log
LAUNCHER_LOG=$LOG_DIR/launcher_forensics_${RESULTS_TAG}_${PLANNER}.log
CARLA_LOG=$LOG_DIR/carla_${RESULTS_TAG}_${PLANNER}.log

export CARLA_ROOT
export PYTHONPATH="$CARLA_ROOT/PythonAPI/carla/dist/carla-0.9.12-py3.7-linux-x86_64.egg:$CARLA_ROOT/PythonAPI/carla:$CARLA_ROOT/PythonAPI:${PYTHONPATH:-}"

cd "$REPO_ROOT"
mkdir -p "$LOG_DIR"

cleanup_port() {
  local phase=$1
  local pids
  pids=$(pgrep -f "CarlaUE4|--world-port=${PORT}|trafficManagerPort ${TM_PORT}|trafficManagerPort=${TM_PORT}" || true)
  if [[ -n "$pids" ]]; then
    echo "[$(date '+%F %T')] [$phase] terminating leftover CARLA/leaderboard processes on port ${PORT}" | tee -a "$RUN_LOG"
    pkill -TERM -f "CarlaUE4|--world-port=${PORT}|trafficManagerPort ${TM_PORT}|trafficManagerPort=${TM_PORT}" || true
    sleep 5
  fi
  pids=$(pgrep -f "CarlaUE4|--world-port=${PORT}|trafficManagerPort ${TM_PORT}|trafficManagerPort=${TM_PORT}" || true)
  if [[ -n "$pids" ]]; then
    echo "[$(date '+%F %T')] [$phase] force-killing leftover CARLA/leaderboard processes on port ${PORT}" | tee -a "$RUN_LOG"
    pkill -KILL -f "CarlaUE4|--world-port=${PORT}|trafficManagerPort ${TM_PORT}|trafficManagerPort=${TM_PORT}" || true
    sleep 2
  fi
}

echo "[$(date '+%F %T')] isolated V2XPNP eval start: tag=${RESULTS_TAG} planner=${PLANNER} gpu=${GPU} port=${PORT}" | tee -a "$RUN_LOG"

mapfile -t SCENARIOS < <(find "$ROUTES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' | sort)
TOTAL=${#SCENARIOS[@]}

for idx in "${!SCENARIOS[@]}"; do
  scenario=${SCENARIOS[$idx]}
  scenario_dir=$ROUTES_DIR/$scenario
  n=$((idx + 1))

  if [[ -f "results/results_driving_custom/${RESULTS_TAG}/${scenario}/results.json" ]]; then
    echo "[$(date '+%F %T')] SCENARIO ${n}/${TOTAL} ${scenario}: existing results.json, skipping" | tee -a "$RUN_LOG"
    continue
  fi

  cleanup_port "before ${scenario}"

  echo "[$(date '+%F %T')] SCENARIO ${n}/${TOTAL} ${scenario}: start" | tee -a "$RUN_LOG"
  set +e
  CONDA_DEFAULT_ENV= DISPLAY=${DISPLAY:-:0} CUDA_VISIBLE_DEVICES=$GPU \
    "$PYTHON" tools/run_custom_eval.py \
      --routes-dir "$scenario_dir" \
      --timeout "$TIMEOUT" \
      --start-carla \
      --carla-forensics \
      --no-planner-dashboard \
      --planner "$PLANNER" \
      --port "$PORT" \
      --traffic-manager-port "$TM_PORT" \
      --results-tag "$RESULTS_TAG" \
      --results-subdir "$scenario" \
      --scenario-name "$scenario" \
      --scenario-retry-limit "$RETRY_LIMIT" \
      --carla-forensics-log-file "$LAUNCHER_LOG" \
      --carla-forensics-server-log-file "$CARLA_LOG"
  rc=$?
  set -e

  echo "[$(date '+%F %T')] SCENARIO ${n}/${TOTAL} ${scenario}: exit_code=${rc}" | tee -a "$RUN_LOG"
  cleanup_port "after ${scenario}"

  if [[ $rc -ne 0 ]]; then
    echo "[$(date '+%F %T')] SCENARIO ${n}/${TOTAL} ${scenario}: failed; continuing to next scenario" | tee -a "$RUN_LOG"
  fi
done

cleanup_port "final"
echo "[$(date '+%F %T')] isolated V2XPNP eval done: tag=${RESULTS_TAG}" | tee -a "$RUN_LOG"
