% smf_orchestration.mzn

int: J; % liczba obszarów
int: K; % liczba kandydatów na lokalizacje SMF

array[1..J] of int: pop;          % populacja w obszarach
array[1..J] of float: req_per_person; % żądania/s na osobę
float: tau; % średni czas trwania sesji [s]

% Obliczenie parametrów ruchu (zmienna pomocnicza, nie decyzyjna)
array[1..J] of float: active_sessions = [ pop[j] * req_per_person[j] * tau | j in 1..J ];

array[1..K] of float: latency;    % pomocnicze 
array[1..K,1..J] of float: latency_kj; % opóźnienie lokalizacja k -> obszar j [ms]
float: Lmax; % dopuszczalne opóźnienie [ms]

int: C;                % pojemność jednej instancji SMF (liczba sesji)
int: Nmin;             % minimalna liczba instancji na lokalizację
int: Nmax;             % maksymalna liczba instancji na lokalizację

float: cost_per_instance; % koszt jednej instancji
float: alpha_scale;       % parametr kary za skalowanie

% --- zmienne decyzyjne ---
array[1..K] of var 0..Nmax: x;         % ile instancji na lokalizacji k
array[1..J,1..K] of var 0..1: assign;  % przypisanie obszaru j do lokalizacji k (0/1)

% 1. Każdy obszar przypisany do dokładnie jednej lokalizacji
constraint forall(j in 1..J) ( sum(k in 1..K)(assign[j,k]) = 1 );

% 2. Przypisanie do lokalizacji dozwolone tylko jeśli latency <= Lmax
constraint forall(j in 1..J, k in 1..K) (
    assign[j,k] = 1 -> latency_kj[k,j] <= Lmax
);

% 3. Zasada pojemności (POPRAWIONA): 
% Suma aktywnych sesji ze wszystkich obszarów przypisanych do k 
% musi być mniejsza lub równa pojemności instancji w k.
constraint forall(k in 1..K)(
    sum(j in 1..J)( assign[j,k] * active_sessions[j] ) <= x[k] * C
);

% 4. Minimalna/maksymalna liczba instancji (zapewnione przez dziedzinę zmiennej x, ale dodajemy Nmin)
constraint forall(k in 1..K)(
    x[k] >= Nmin
);

% Funkcja celu: minimalizuj koszt utrzymania instancji
var float: total_cost = sum(k in 1..K)( cost_per_instance * x[k] );

solve minimize total_cost;

output [
  "x = " ++ show(x) ++ "\n",
  "assign = " ++ show(assign) ++ "\n",
  "active_sessions = " ++ show(active_sessions) ++ "\n",
  "total_cost = " ++ show(total_cost) ++ "\n"
];