module Hopac.Tests.Job

open System
open Expecto
open Expecto.Flip
open Hopac
open Hopac.Infixes

/// A dummy disposable reference type
type DummyDisposable () =
  interface IDisposable with
    member __.Dispose () = ()

/// A disposable that increments a counter when disposed (thread-safe)
type DisposeCounter (x: int ref) =
  interface IDisposable with
    member __.Dispose () =
      lock typeof<DisposeCounter>
        (fun _ -> x.Value <- x.Value + 1)

[<Tests>]
let __ = testList "Job" [

  testList "disposables" [

    testCase "Job.using keeps the correct disposable reference" <| fun _ ->
      let x = ref 0
      let dummy = new DummyDisposable()
      Job.using dummy Job.result |> run
      |> Expect.equal "Correct reference returned" dummy

    testCase "Job.using successfully disposes once" <| fun _ ->
      let x = ref 0
      let counter = new DisposeCounter(x)
      Job.using counter Job.result |> run |> ignore
      Expect.equal "Disposal occurred" 1 x.Value

    testProp "Job.using successfully disposes n times" <|
      fun (n: SmallInt) ->
        let n, x = n.si, ref 0
        [ for _ in 1..n ->
            Job.using (new DisposeCounter(x)) Job.result ]
        |> Job.conIgnore |> run
        Expect.equal (sprintf "%i disposals occurred" n) n x.Value
  ]

  testList "exceptions" [

    testCase "Job.catch returns a raised exception" <| fun _ ->
      Job.delay (fun () -> failwith "error")
      |> Job.catch >>- function
        | Choice1Of2 _ -> false
        | Choice2Of2 ex -> ex.Message = "error"
      |> run |> Expect.isTrue "Raised exception returned"

    testCase "Job.catch catches both exceptions from <*>" <| fun _ ->
      Job.delay (fun () -> raise <| ExpectedExn 1)
      <*> Job.delay (fun () -> raise <| ExpectedExn 2)
      |> Job.catch >>- getCaughtExnDiff [ ExpectedExn 1; ExpectedExn 2 ]
      |> run |> Expect.equal "Exceptions match exactly" []

    testProp "Job.catch catches n exceptions from Job.raises" <|
      fun (n: SmallInt) ->
        let n = n.si
        let expected = [ for i in 1..n -> ExpectedExn i ]
        [ for i in 1..n -> Job.raises <| ExpectedExn i ]
        |> Job.conIgnore |> Job.catch >>- getCaughtExnDiff expected
        |> run |> Expect.equal "All n exceptions caught" []
  ]

]