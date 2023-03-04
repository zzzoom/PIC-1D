"""The routine below evaluates the electron number density on an evenly spaced mesh given the 
instantaneous electron coordinates.

Evaluates electron number density n(1:J) from 
array r(1:N) of electron coordinates.

shift can have the values 0 or 1/2 depending whether we want the density at gridpoint or at midpoints.
"""
function get_density!(u, n, par_grid, shift)
  N, L, J, dx, order = par_grid
  n0 = N/L
  r = view(u,1:N)
  fill!(n,0.0)
  # Evaluate number density.
  bound = Int64(ceil(order/2))
  for i in 1:N
    @inbounds j, y = get_index_and_y(r[i],J,L)
    y += - shift
    for l in (-bound):(bound+1) 
      @inbounds n[mod1(j + l, J)] += Shape(order, -y + l) / dx / n0; # the dx here is from the different definition from the paper
    end
  end
  return n[:] # return rho directly (we need to subtract 1 in cases where we assume positive particles, but this is done elsewhere.)
end

function get_density_2D!(u, n, par_grid, shift)
  N, Box, J, order = par_grid
  #vol = volume(Box)
  fill!(n,0.0)
  #n0 = N/vol # correct expression but not needed
  D = 2
  if D != length(J) 
    error("dimension mismach")
   end
  n0 = N
  j = [1,1]
  y = [0.0,0.0]
  #@show u
  # Evaluate number density.
  bound = Int64(ceil(order/2))
  for i in 1:N
    s = (i-1)*2D + 1
    u_r = view(u,s:(s+D-1))
    #@inbounds j, y = get_index_and_y!(j,y,u_r,J,Box)
    @inbounds get_index_and_y!(j,y,u_r,J,Box)
    y .= y .- shift # shift must be the same in all directions!
    for l in (-bound):(bound+1) 
      for m in (-bound):(bound+1)
      #@inbounds n[mod1(j + l, J)] += Shape(order, -y + l) / dx / n0; # the dx here is from the different definition from the paper
      @inbounds n[mod1(j[1] + l, J[1]), mod1(j[2] + m, J[2])] += Shape(order, -y[1] + l) * Shape(order, -y[2] + m)/ n0
      end
    end
  end
  return n[:,:] # return rho directly (we need to subtract 1 in cases where we assume positive particles, but this is done elsewhere.)
end

function get_density_threads_2D!(u, n, par, shift)
  #par_grid, Tn, j, y = par # no vale la pena en cuanto a tiempo ni memoria
  par_grid, Tn = par
  N, Box, J, order = par_grid
  D = 2
  if D != length(J) 
    error("dimension mismach")
   end
  #u_r = Array{Float64}(undef,(D,nthreads()))
  j = Array{Int64}(undef,2,nthreads())
  j .= 1
  y = Array{Float64}(undef,2,nthreads())
  y .= 0.0
  Tn .= 0.0 
  #s = [0 for i in 1:nthreads()]
  n0 = N
  # Evaluate number density.
  bound = Int64(ceil(order/2))
  @threads  for i in 1:N
              #s[threadid()] = (i-1)*2D + 1
              #u_r[:,threadid()] = view(u,s[threadid()]:(s[threadid()]+D-1))
              #j[:,threadid()], y[:,threadid()] = get_index_and_y!(j[:,threadid()], y[:,threadid()], u_r[:,threadid()],J , Box) 
              j[:,threadid()], y[:,threadid()] = get_index_and_y!(j[:,threadid()], y[:,threadid()], u[(i-1)*2D + 1:(i-1)*2D + D],J , Box) 
      @inbounds  y[:,threadid()] .= y[:,threadid()] .- shift # shift must be the same in all directions!
              for l in (-bound):(bound+1)
                for m in (-bound):(bound+1)
      @inbounds   Tn[mod1(j[1,threadid()] + l, J[1]), mod1(j[2,threadid()] + m, J[2]), threadid()] += Shape(order, -y[1,threadid()] + l) * Shape(order, -y[2,threadid()] + m)
                end
              end
            end
  n .= 0.0
  #@show n, Tn
  @threads for j in 1:J[2]
            for i in 1:J[1]
              for t in 1:nthreads()
                n[i,j] += Tn[i,j,t]/n0 # the dx here is from the different definition from the paper
              end
            end
          end
  return n[:,:] # return rho directly (we need to subtract 1 in cases where we assume positive particles, but this is done elsewhere.)
end

function get_density_threads!(u, n, p, shift)
  par_grid, Tn = p
  N, L, J, dx, order = par_grid
  j = fill(Int64(1),nthreads()) 
  y = fill(Float64(1.0),nthreads())
  Tn .= zeros(Float64)
  n0 = N/L
  bound = Int64(ceil(order/2))
  # Evaluate number density.
  @threads for i in 1:N
    @inbounds j[threadid()], y[threadid()] = get_index_and_y(u[i], J, L)
    y[threadid()] += - shift
    for l in (-bound):-j[threadid()]
      @inbounds Tn[J + j[threadid()] + l, threadid()] += Shape(order, -y[threadid()] + l) 
    end
    for l in max(-bound,-j[threadid()]+1):min((bound+1),J-j[threadid()])
      @inbounds Tn[j[threadid()] + l, threadid()] += Shape(order, -y[threadid()] + l) 
    end
    for l in J-j[threadid()]+1:(bound+1)
      @inbounds Tn[j[threadid()] - J + l, threadid()] += Shape(order, -y[threadid()] + l) 
    end
  end
  n .= zeros(Float64)
  @threads for i in 1:J
    for t in 1:nthreads()
      @inbounds n[i] += Tn[i, t]/dx/n0 # the dx here is from the different definition from the paper
    end
  end
  return n[:]
end


function get_total_charge(ρ,par)
  J, dx = par
  Q = 0.0
  for i in 1:J
      Q += ρ[i]
  end
  return Q * dx
end

function get_total_charge(ρ,Vol)
  Q = sum(ρ)*Vol/length(ρ)
end

"""The routine below evaluates the electron current on an evenly spaced mesh given the instantaneous electron coordinates.
// Evaluates electron number density S(0:J-1) from 
// array r(0:N-1) of electron coordinates.
"""

function get_current_rel!(u, S, par_grid)
  N, L, J, dx, order = par_grid
  r = view(u,1:N)
  p = view(u,N+1:2N) # in the relativistic version we compute p instead of v
  fill!(S,0.0)
  n0 = N/L
  bound = Int64(ceil(order/2))
  for i in 1:N
    @inbounds j, y = get_index_and_y(r[i],J,L)
    @inbounds v = p2v(p[i]) / dx / n0 # the dx here is from the different definition from the paper
    for l in (-bound):(bound+1) 
      @inbounds S[mod1(j + l, J)] += Shape(order, -y + l) * v;
    end
  end
  return S[:] # allready normalized with n0
end

function get_current_rel_threads!(u, S, p)
  par_grid, TS = p
  N, L, J, dx, order = par_grid
  j = fill(Int64(1),nthreads()) 
  y = fill(Float64(1.0),nthreads())
  TS .= zeros(Float64)
  n0 = N/L
  bound = Int64(ceil(order/2))
  @threads for i in 1:N
    @inbounds j[threadid()], y[threadid()] = get_index_and_y(u[i], J, L)
    @inbounds v = p2v(u[N+i]) / dx / n0 # the dx here is from the different definition from the paper
    for l in (-bound):-j[threadid()]
      @inbounds TS[J + j[threadid()] + l, threadid()] += Shape(order, -y[threadid()] + l) * v
    end
    for l in max(-bound,-j[threadid()]+1):min(bound+1,J-j[threadid()])
      @inbounds TS[j[threadid()] + l, threadid()] += Shape(order, -y[threadid()] + l) * v
    end
    for l in J-j[threadid()]+1:(bound+1)
      @inbounds TS[j[threadid()] - J + l, threadid()] += Shape(order, -y[threadid()] + l) * v
    end
    #= 
    for l in (-order):order
       @inbounds TS[mod1(j + l, J), threadid()] += Shape(order, -y + l) * v
    end
    =#
  end
  S .= zeros(Float64)
  @threads for j in 1:J
    for t in 1:nthreads()
      @inbounds S[j] += TS[j, t]
    end
  end
  S[:]
end
    
function get_current_rel_2D!(u, S, par_grid;shift=0.0)
  N, Box, J, order = par_grid 
  D = 2
   if D != length(J) 
    error("dimension mismach")
   end
  #vol = volume(Box)
  bound = Int64(ceil(order/2))
  fill!(S,[0.0,0.0])
  v = Array{Float64}(undef,2)
  #n0 = N/vol # correct expression but not needed
  n0 = N
  for i in 1:N
    s = (i-1)*2D + 1
    r = view(u,s:s+D-1)
    p = view(u,s+D:s+2*D-1) # in the relativistic version we compute p instead of v
    j = [1,1]
    y = [0.0,0.0]
    @inbounds j, y = get_index_and_y!(j,y,r,J,Box)
    @inbounds  y[:] .= y[:] .- shift # shift must be the same in all directions!
    #@inbounds v = p2v(p) / vol / n0 # correct but can be made simpler
    @inbounds v = p2v(p) / n0 # dividimos aquí para hacerlo más eficiente.
    for l in (-bound):(bound+1) 
      for m in (-bound):(bound+1)
      @inbounds S[mod1(j[1] + l, J[1]), mod1(j[2] + m, J[2])] += Shape(order, -y[1] + l) * Shape(order, -y[2] + m) * v;
      end
    end
  end
  return S[:,:] # allready normalized with n0
end

"""
using @fastmath makes errors!
"""
function get_current_threads_2D_vector!(u, S, par; shift=0.0)
  #par_grid, Tn, j, y = par # no vale la pena en cuanto a tiempo ni memoria
  par_grid, TS = par
  N, Box, J, order = par_grid
  D = 2::Int64
  if D != length(J) 
    error("dimension mismach")
  end
  bound = Int64(ceil(order/2))

  #u_r = Array{Float64}(undef,(D,nthreads()))
  j = Array{Int64}(undef,2,nthreads())
  j .= 1
  y = Array{Float64}(undef,2,nthreads())
  y .= 0.0
  v = Array{Float64}(undef,2,nthreads())
  TS .= 0.0 
  #s = [0 for i in 1:nthreads()]
  n0 = N
  # Evaluate number density.
   @threads for i in 1:N
              #s = (i-1)*2D + 1
              #r = view(u,s:s+D-1)
              #p = view(u,s+D:s+2*D-1) # in the relativistic version we compute p instead of v
       v[:,threadid()] = p2v(u[i*2D - D + 1:i*2D]) / n0 # dividimos aquí para hacerlo más eficiente.
              #s[threadid()] = (i-1)*2D + 1
              #u_r[:,threadid()] = view(u,s[threadid()]:(s[threadid()]+D-1))
              #j[:,threadid()], y[:,threadid()] = get_index_and_y!(j[:,threadid()], y[:,threadid()], u_r[:,threadid()],J , Box) 
       j[:,threadid()], y[:,threadid()] = get_index_and_y!(j[:,threadid()], y[:,threadid()], u[(i-1)*2D + 1:(i-1)*2D + D],J , Box) 
       y[:,threadid()] .= y[:,threadid()] .- shift # shift must be the same in all directions!
              for l in (-bound):(bound+1)
                for m in (-bound):(bound+1)
       TS[:,mod1(j[1,threadid()] + l, J[1]), mod1(j[2,threadid()] + m, J[2]), threadid()] += Shape(order, -y[1,threadid()] + l) * Shape(order, -y[2,threadid()] + m)*v[:,threadid()]
                end
              end
            end
  fill!(S,[0.0,0.0])
  #S .= [0.0,0.0]
  #@show n, Tn
  @threads for j in 1:J[2]
            for i in 1:J[1]
              for t in 1:nthreads()
                 S[i,j] += TS[:,i,j,t] # the dx here is from the different definition from the paper
              end
            end
          end
  #return S[:,:] # return rho directly (we need to subtract 1 in cases where we assume positive particles, but this is done elsewhere.)
end

"""
version of get_current_threads_2D but with shorter stencils and different indexing for the arrays.
The output is an array of type (2,J1,J2). Checked and working OK against the other version and against the serial version.
"""
function get_current_threads_2D!(u::Array{Float64,1}, S::Array{Float64,3}, par; shift=0.0) #WITH DIFFERENT LAYOUT
  #par_grid, Tn, j, y = par # no vale la pena en cuanto a tiempo ni memoria
  par_grid, TS = par
  N, Box, J, order = par_grid
  D = 2::Int64
  bound = Int64(ceil(order/2))
  if D != length(J) 
    error("dimension mismach")
   end
  #u_r = Array{Float64}(undef,(D,nthreads()))
  j = Array{Int64}(undef,2,nthreads())
  j .= 1
  y = Array{Float64}(undef,2,nthreads())
  y .= 0.0
  v = Array{Float64}(undef,2,nthreads())
  TS .= 0.0 
  #s = [0 for i in 1:nthreads()]
  n0 = N
  # Evaluate number density.
  @fastmath @threads for i in 1:N
              #s = (i-1)*2D + 1
              #r = view(u,s:s+D-1)
              #p = view(u,s+D:s+2*D-1) # in the relativistic version we compute p instead of v
      @inbounds v[:,threadid()] = p2v(u[i*2D - D + 1:i*2D]) / n0 # dividimos aquí para hacerlo más eficiente.
              #s[threadid()] = (i-1)*2D + 1
              #u_r[:,threadid()] = view(u,s[threadid()]:(s[threadid()]+D-1))
              #j[:,threadid()], y[:,threadid()] = get_index_and_y!(j[:,threadid()], y[:,threadid()], u_r[:,threadid()],J , Box) 
      @inbounds j[:,threadid()], y[:,threadid()] = get_index_and_y!(j[:,threadid()], y[:,threadid()], u[(i-1)*2D + 1:(i-1)*2D + D],J , Box) 
      @inbounds y[:,threadid()] .= y[:,threadid()] .- shift # shift must be the same in all directions!
              for l in (-bound):(bound+1) 
                for m in (-bound):(bound+1)
      @inbounds TS[threadid(),:,mod1(j[1,threadid()] + l, J[1]), mod1(j[2,threadid()] + m, J[2])] += Shape(order, -y[1,threadid()] + l) * Shape(order, -y[2,threadid()] + m)*v[:,threadid()]
                end
              end
            end

  fill!(S,Float64(0.0))
  #S .= [0.0,0.0]
  #@show n, Tn
  @fastmath @threads for t in 1:nthreads()
            for j in 1:J[2]
              for i in 1:J[1] 
                for l in 1:2
                @inbounds  S[l,i,j] += TS[t,l,i,j] # the dx here is from the different definition from the paper
                end
              end
            end
          end
  #return S[:,:] # return rho directly (we need to subtract 1 in cases where we assume positive particles, but this is done elsewhere.)
end

