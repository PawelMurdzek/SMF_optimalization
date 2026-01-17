%%%% MODEL: smf_orchestration.mzn %%%%

% --------------------------
% DEKLARACJA DANYCH (bez wartości)
% --------------------------

int: J;              % liczba regionów
int: K;              % liczba lokalizacji
int: R;              % liczba typów zasobów

array[1..R] of float: smf_req;
array[1..K,1..R] of float: loc_resources;
array[1..J,1..K] of bool: connected;

array[1..J] of int: pop;
array[1..J] of float: req_per_person;
float: tau;

array[1..K,1..J] of float: latency_kj;

float: Lmax;
int: C;
int: Nmin;
float: cost_per_instance;

float: weight_cost;
float: weight_latency;
float: weight_balance;

% --------------------------
% PARAMETRY PRZELICZANE
% --------------------------

array[1..J] of float: active_sessions =
    [ pop[j] * req_per_person[j] * tau | j in 1..J ];

array[1..K] of int: max_cap =
    [ min([ floor(loc_resources[k,r] / smf_req[r]) | r in 1..R ]) | k in 1..K ];

int: system_max_cap = max(max_cap);
float: max_flow = max(active_sessions) * 1.1;

array[1..J,1..K] of float: flow_limiter =
    array2d(1..J,1..K,
        [ connected[j,k] * (latency_kj[k,j] <= Lmax) 
          | j in 1..J, k in 1..K ]);

% --------------------------
% ZMIENNE
% --------------------------

array[1..K] of var 0..system_max_cap: x;
array[1..J,1..K] of var 0.0..max_flow: flow;

var 0.0..1.0: max_util;

% --------------------------
% OGRANICZENIA
% --------------------------

% Conservation of flow
constraint forall(j in 1..J)(
    sum(k in 1..K)(flow[j,k]) = active_sessions[j]
);

% Connectivity and latency
constraint forall(j in 1..J, k in 1..K)(
    flow[j,k] <= max_flow * flow_limiter[j,k]
);

% Capacity
constraint forall(k in 1..K)(
    sum(j in 1..J)(flow[j,k]) <= x[k] * C
);

% Resource constraints
constraint forall(k in 1..K, r in 1..R)(
    x[k] * smf_req[r] <= loc_resources[k,r]
);

% Minimum redundancy
constraint forall(k in 1..K)( x[k] >= Nmin );

% Load balancing
constraint forall(k in 1..K)(
    sum(j in 1..J)(flow[j,k]) <= max_util * (x[k] * C)
);

% --------------------------
% FUNKCJA CELU
% --------------------------

var float: total_cost =
    sum(k in 1..K)( cost_per_instance * x[k] );

float: total_system_sessions = sum(active_sessions);

var float: global_latency_sum =
    sum(j in 1..J, k in 1..K)( flow[j,k] * latency_kj[k,j] );

var float: avg_latency = global_latency_sum / total_system_sessions;

solve minimize 
    weight_cost * total_cost
  + weight_latency * avg_latency
  + weight_balance * max_util * 100;

% --------------------------
% OUTPUT
% --------------------------


output [
  "======================================================\n",
  "=== RAPORT ALOKACJI SMF ===\n",
  "======================================================\n",
  "1. KONFIGURACJA ZASOBÓW\n",
  "   Liczba Regionów (J): " ++ show(J) ++ "\n",
  "   Liczba Lokalizacji (K): " ++ show(K) ++ "\n",
  "   Wagi (Koszt/Opóźnienie/Balans): " ++ show(weight_cost) ++ " / " ++ show(weight_latency) ++ " / " ++ show(weight_balance) ++ "\n\n",

  "2. ROZMIESZCZENIE INSTANCJI (Zmienna x)\n"
] ++
[
  "   Lokalizacja " ++ show(k) ++ ": " ++ show(x[k]) ++ " instancji (Max Cap: " ++ show(x[k]*C) ++ " sesji)\n"
  | k in 1..K
] ++
[
  "\n3. SZCZEGÓŁOWY PRZEPŁYW RUCHU (Flow)\n",
  "   (Skąd -> Dokąd : Ilość Sesji | Opóźnienie)\n"
] ++
[
  if fix(flow[j,k]) > 0.0 then
    "   Region " ++ show(j) ++ " -> SMF " ++ show(k) ++ 
    " : " ++ show_float(6, 1, flow[j,k]) ++ " sesji | " ++ show(latency_kj[k,j]) ++ "ms\n"
  else "" endif
  | j in 1..J, k in 1..K
] ++
[
  "\n4. METRYKI KOŃCOWE\n",
  "   Szczytowe zużycie (Max Util): " ++ show_float(4, 2, max_util * 100) ++ "%\n",
  "   Średnie opóźnienie (Avg Latency): " ++ show_float(4, 2, avg_latency) ++ " ms\n",
  "   Całkowity koszt (Total Cost): " ++ show_float(8, 2, total_cost) ++ "\n",
  "   Funkcja celu (Objective): " ++ show((weight_cost * total_cost) + (weight_latency * avg_latency) + (weight_balance * max_util * 100)) ++ "\n",
  "======================================================\n"
];
