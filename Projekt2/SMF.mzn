% --------------------------
% 1. DEKLARACJA DANYCH (WEJŚCIE)
% --------------------------

int: J;              % Liczba regionów
int: K;              % Liczba lokalizacji (Datacenters)
int: R;              % Liczba typów zasobów (CPU, RAM, SSD)

array[1..R] of float: smf_req;             % Zasoby na 1 instancję
array[1..K,1..R] of float: loc_resources;  % Zasoby dostępne w DC
array[1..J,1..K] of bool: connected;       % Macierz połączeń

array[1..J] of int: pop;                   % Populacja w regionie
array[1..J] of float: req_per_person;      % Współczynnik żądań (lambda_i)
float: tau;                                % Średni czas trwania sesji (1/mu)

array[1..K,1..J] of float: latency_kj;     % Opóźnienia

float: Lmax;                               % Max dopuszczalne opóźnienie
int: Nmin;                                 % Min liczba instancji (redundancja)
float: cost_per_instance;                  % Koszt jednej instancji

% Wagi funkcji celu
float: weight_cost;
float: weight_latency;
float: weight_balance;

% --------------------------
% 2. TABELA ERLANGA B (Stałe z obrazka)
% --------------------------

% Wybieramy kolumnę dla B = 1.0% (prawdopodobieństwo blokady 1%)
% Indeks tablicy odpowiada liczbie N (instancji/kanałów) od 1 do 20
array[1..20] of float: erlang_table = [
    0.0101, 0.1526, 0.4555, 0.8694, 1.361,   % N: 1-5
    1.909,  2.501,  3.128,  3.783,  4.461,   % N: 6-10
    5.160,  5.876,  6.607,  7.352,  8.108,   % N: 11-15
    8.875,  9.652,  10.44,  11.23,  12.03    % N: 16-20
];

% Ponieważ Twoja populacja generuje tysiące sesji, a tabela Erlanga 
% operuje na jednostkach, wprowadzamy mnożnik wydajności.
% Przykład: "1 jednostka w tabeli Erlanga = 10 000 rzeczywistych sesji"
float: capacity_scale = 40000.0; 

% --------------------------
% 3. PARAMETRY PRZELICZANE
% --------------------------

% Obliczanie natężenia ruchu A = lambda * (1/mu) w Erlangach dla każdego regionu
array[1..J] of float: regional_traffic_erlangs =
    [ (pop[j] * req_per_person[j]) * tau | j in 1..J ];

float: total_traffic = sum(regional_traffic_erlangs);

% Maksymalna liczba instancji, które fizycznie zmieszczą się w lokalizacji k (wg zasobów)
array[1..K] of int: hardware_limit =
    [ min([ floor(loc_resources[k,r] / smf_req[r]) | r in 1..R ]) | k in 1..K ];

% Ograniczenie techniczne do rozmiaru tabeli (max 20)
array[1..K] of int: max_N = [ min(20, hardware_limit[k]) | k in 1..K ];

% Macierz dopuszczalnych połączeń (Uwzględnia: 'connected' ORAZ 'Lmax')
array[1..J,1..K] of bool: possible_flow =
    array2d(1..J,1..K,
        [ connected[j,k] /\ (latency_kj[k,j] <= Lmax) 
          | j in 1..J, k in 1..K ]);

% --------------------------
% 4. ZMIENNE DECYZYJNE
% --------------------------

array[1..K] of var 0..20: x;                   % Liczba instancji N w lokalizacji k
array[1..J,1..K] of var 0.0..total_traffic: flow; % Przepływ ruchu (w Erlangach)

var 0.0..1.0: max_util;                        % Wykorzystanie pojemności Erlangowskiej

% --------------------------
% 5. OGRANICZENIA
% --------------------------

% CAŁKOWITY RUCH: Cały ruch z regionu musi być obsłużony przez dostępne SMF
constraint forall(j in 1..J)(
    sum(k in 1..K)(flow[j,k]) = regional_traffic_erlangs[j]
);

% DOSTĘPNOŚĆ I LATENCY: Ruch płynie tylko tam, gdzie jest połączenie i niskie opóźnienie
constraint forall(j in 1..J, k in 1..K)(
    if not possible_flow[j,k] then flow[j,k] = 0.0 else true endif
);

% POJEMNOŚĆ ERLANGA: Ruch w lokalizacji k nie może przekroczyć wartości z tabeli dla N instancji
constraint forall(k in 1..K)(
    if x[k] > 0 then
        sum(j in 1..J)(flow[j,k]) <= erlang_table[x[k]] * capacity_scale
    else
        sum(j in 1..J)(flow[j,k]) = 0.0
    endif
);

% LIMIT HARDWARE: Nie możemy postawić więcej instancji niż pozwalają zasoby (CPU/RAM/SSD)
constraint forall(k in 1..K)(
    x[k] <= max_N[k]
);

% REDUNDANCJA: Jeśli lokalizacja jest używana, musi mieć co najmniej Nmin instancji
constraint forall(k in 1..K)(
    x[k] > 0 -> x[k] >= Nmin
);

% LOAD BALANCING: Obliczanie maksymalnego stopnia wykorzystania kanałów Erlanga
constraint forall(k in 1..K)(
    if x[k] > 0 then
        sum(j in 1..J)(flow[j,k]) <= max_util * (erlang_table[x[k]] * capacity_scale)
    else true endif
);

% --------------------------
% 6. FUNKCJA CELU
% --------------------------

var float: total_cost = sum(k in 1..K)( cost_per_instance * x[k] );

var float: avg_latency = 
    sum(j in 1..J, k in 1..K)( flow[j,k] * latency_kj[k,j] ) / total_traffic;

solve minimize 
    weight_cost * total_cost
  + weight_latency * avg_latency
  + weight_balance * max_util * 100.0;

% --------------------------
% 7. FORMATOWANIE WYJŚCIA
% --------------------------

output [
  "======================================================\n",
  "=== RAPORT SMF: MODEL KOLEJKOWY ERLANG B (B=1%) ===\n",
  "======================================================\n",
  "1. STATYSTYKI RUCHU\n",
  "   Całkowite obciążenie sieci: " ++ show_float(7, 2, total_traffic) ++ " Erlangów\n\n",

  "2. ALOKACJA INSTANCJI (Zmienna x)\n"
] ++
[
  "   DC " ++ show(k) ++ ": " ++ show(x[k]) ++ " instancji | Pojemność Erlanga: " ++ 
  (if fix(x[k]) > 0 then show_float(7, 2, erlang_table[fix(x[k])] * capacity_scale) else "0.00" endif) ++ " sesji\n"
  | k in 1..K
] ++
[
  "\n3. PRZEPŁYW RUCHU (Region -> DC)\n"
] ++
[
  if fix(flow[j,k]) > 0.0 then
    "   Reg " ++ show(j) ++ " -> DC " ++ show(k) ++ 
    " : " ++ show_float(7, 1, flow[j,k]) ++ " Erl | Latency: " ++ show(latency_kj[k,j]) ++ "ms\n"
  else "" endif
  | j in 1..J, k in 1..K
] ++
[
  "\n4. KLUCZOWE WSKAŹNIKI\n",
  "   Max Util (Erlang Capacity): " ++ show_float(4, 2, max_util * 100.0) ++ "%\n",
  "   Średnie Opóźnienie: " ++ show_float(4, 2, avg_latency) ++ " ms\n",
  "   Koszt Całkowity: " ++ show_float(6, 2, total_cost) ++ "\n",
  "======================================================\n"
];