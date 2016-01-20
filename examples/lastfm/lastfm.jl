using RecSys

import RecSys: train, recommend, rmse

if isless(Base.VERSION, v"0.5.0-")
    using SparseVectors
end

type MusicRec
    trainingset::FileSpec
    artist_names::FileSpec
    artist_map::FileSpec
    rec::ALSWR
    artist_mat::Nullable{Dict{Int64,AbstractString}}

    function MusicRec(trainingset::FileSpec, artist_names::FileSpec, artist_map::FileSpec)
        T, N = map_artists(trainingset, artist_names, artist_map)
        new(trainingset, artist_names, artist_map, ALSWR(SparseMat(T)), Nullable(N))
    end
end

function read_artist_map(artist_map::FileSpec)
    t1 = time()
    RecSys.logmsg("reading artist map")
    A = read_input(artist_map)
    valid = map(x->isa(x, Integer), A)
    valid = valid[:,1] & valid[:,2]
    Avalid = convert(Matrix{Int64}, A[valid, :])

    amap = Dict{Int64,Int64}()
    for idx in 1:size(Avalid,1)
        bad_id = Avalid[idx, 1]
        good_id = Avalid[idx, 2]
        amap[bad_id] = good_id
    end
    RecSys.logmsg("read artist map in $(time()-t1) secs")
    amap
end

function read_trainingset(trainingset::FileSpec, amap::Dict{Int64,Int64})
    t1 = time()
    RecSys.logmsg("reading trainingset")
    T = read_input(trainingset)
    for idx in 1:size(T,1)
        artist_id = T[idx,2]
        if artist_id in keys(amap)
            T[idx,2] = amap[artist_id]
        end
    end
    users   = convert(Vector{Int64},   T[:,1])
    artists = convert(Vector{Int64},   T[:,2])
    ratings = convert(Vector{Float64}, T[:,3])
    S = sparse(users, artists, ratings)
    RecSys.logmsg("read trainingset in $(time()-t1) secs")
    S
end

function read_artist_names(artist_names::FileSpec, amap::Dict{Int64,Int64})
    t1 = time()
    RecSys.logmsg("reading artist names")
    A = read_input(artist_names)
    name_map = Dict{Int64,AbstractString}()
    for idx in 1:size(A,1)
        artist_id = A[idx, 1]
        artist_name = A[idx, 2]
        (isa(artist_id, Integer) && isa(artist_name, AbstractString)) || continue

        if artist_id in keys(amap)
            artist_id = amap[artist_id]
            (artist_id in keys(name_map)) || (name_map[artist_id] = artist_name)
        else
            name_map[artist_id] = artist_name
        end
    end
    RecSys.logmsg("read artist names in $(time()-t1) secs")
    name_map
end

function map_artists(trainingset::FileSpec, artist_names::FileSpec, artist_map::FileSpec)
    amap = read_artist_map(artist_map)
    T = read_trainingset(trainingset, amap)
    N = read_artist_names(artist_names, amap)
    T, N
end

function artist_names(rec::MusicRec)
    if isnull(rec.artist_mat)
        T, N = map_artists(rec.trainingset, rec.artist_names, rec.artist_map)
        rec.artist_mat = Nullable(N)
    end

    get(rec.artist_mat)
end

train(musicrec::MusicRec, args...) = train(musicrec.rec, args...)
rmse(musicrec::MusicRec) = rmse(musicrec.rec)
recommend(musicrec::MusicRec, args...; kwargs...) = recommend(musicrec.rec, args...; kwargs...)

function print_list(mat::Dict, idxs::Vector{Int}, header::AbstractString)
    if !isempty(idxs)
        println(header)
        for idx in idxs
            println("[$idx] $(mat[idx])")
        end
    end
end

function print_recommendations(rec::MusicRec, recommended::Vector{Int}, listened::Vector{Int}, nexcl::Int)
    anames = artist_names(rec)

    print_list(anames, listened, "Already listened:")
    (nexcl == 0) || println("Excluded $(nexcl) artists already listened")
    print_list(anames, recommended, "Recommended:")
    nothing
end

function test(dataset_path)
    ratings_file = DlmFile(joinpath(dataset_path, "user_artist_data.txt"))
    artist_names = DlmFile(joinpath(dataset_path, "artist_data.txt"); dlm='\t', quotes=false)
    artist_map = DlmFile(joinpath(dataset_path, "artist_alias.txt"))

    rec = MusicRec(ratings_file, artist_names, artist_map)
    train(rec, 20, 20)

    err = rmse(rec)
    println("rmse of the model: $err")

    println("recommending existing user:")
    print_recommendations(rec, recommend(rec, 9875)...)

    println("recommending anonymous user:")
    u_idmap = RecSys.user_idmap(rec.rec.inp)
    i_idmap = RecSys.item_idmap(rec.rec.inp)
    # take user 9875
    actual_user = findfirst(u_idmap, 9875)
    rated_anon, ratings_anon = RecSys.items_and_ratings(rec.rec.inp, actual_user)
    actual_movie_ids = i_idmap[rated_anon]
    sp_ratings_anon = SparseVector(maximum(i_idmap), actual_movie_ids, ratings_anon)
    print_recommendations(rec, recommend(rec, sp_ratings_anon)...)

    println("saving model to model.sav")
    save(rec, "model.sav")
    nothing
end
