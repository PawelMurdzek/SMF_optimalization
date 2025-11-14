% smf_orchestration_objective.mzn

int: J; 
int: K; 
int: R; 

% --- Resources & Topology ---
array[1..K, 1..R] of float: loc_resources;  
array[1..R] of float: smf_req;              
array[1..J, 1..K] of bool: connected;       

% --- Standard Data ---
array[1..J] of int: pop;
array[1..J] of float: req_per_person;
float: tau;
array[1..J] of float: active_sessions = [ pop[j] * req_per_person[j] * tau | j in 1..J ];

array[1..K,1..J] of float: latency_kj; 
float: Lmax;
int: C; 
int: Nmin;

float: cost_per_instance;

% --- Optimization Weights (NEW) ---
float: weight_cost;    % Priority for saving money
float: weight_latency; % Priority for speed (latency)

% --- Decision Variables ---
array[1..K] of var int: x;             
array[1..J,1..K] of var 0..1: assign;

% --- Constraints ---
constraint forall(j in 1..J) ( sum(k in 1..K)(assign[j,k]) = 1 );

constraint forall(j in 1..J, k in 1..K) (
    assign[j,k] = 1 -> latency_kj[k,j] <= Lmax
);

constraint forall(j in 1..J, k in 1..K) (
    assign[j,k] = 1 -> connected[j,k] = true
);

constraint forall(k in 1..K)(
    sum(j in 1..J)( assign[j,k] * active_sessions[j] ) <= x[k] * C
);

constraint forall(k in 1..K, r in 1..R)(
    x[k] * smf_req[r] <= loc_resources[k,r]
);

constraint forall(k in 1..K)( x[k] >= Nmin );

% --- OBJECTIVE FUNCTION CALCULATION ---

% 1. Financial Cost
var float: total_cost = sum(k in 1..K)( cost_per_instance * x[k] );

% 2. Average System Latency
% (Sum of latency for every single session) / (Total number of sessions)
float: total_sessions = sum(active_sessions);
var float: total_latency_mass = sum(j in 1..J, k in 1..K)(
    assign[j,k] * active_sessions[j] * latency_kj[k,j]
);
var float: avg_latency = total_latency_mass / total_sessions;

% 3. Combined Objective
% We minimize the weighted sum of both
solve minimize (weight_cost * total_cost) + (weight_latency * avg_latency);

output [
  "--- RESULTS ---\n",
  "Instances (x): " ++ show(x) ++ "\n",
  "Assignments: \n" ++ show2d(assign) ++ "\n",
  "--- METRICS ---\n",
  "Total Cost ($): " ++ show(total_cost) ++ "\n",
  "Avg Latency (ms): " ++ show(avg_latency) ++ "\n",
  "Weighted Score: " ++ show((weight_cost * total_cost) + (weight_latency * avg_latency))
];