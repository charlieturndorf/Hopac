﻿// Copyright (C) by Housemarque, Inc.

namespace Hopac {
  using Hopac.Core;
  using System;
  using System.Runtime.CompilerServices;
  using System.Threading;

  /// <summary>Represents a promise to produce a result at some point in the
  /// future.</summary>
  public class Promise<T> : Alt<T> {
    internal T Value;
    internal volatile int State;
    internal Cont<T> Readers;

    internal const int Failed = -2;
    internal const int Completed = -1;
    internal const int Running = 0;
    internal const int Locked = 1;

    [MethodImpl(AggressiveInlining.Flag)]
    internal Promise() { }

    /// <summary>Creates a promise with the given value.</summary>
    [MethodImpl(AggressiveInlining.Flag)]
    public Promise(T value) {
      this.State = Completed;
      this.Value = value;
    }

    /// <summary>Creates a promise with the given failure exception.</summary>
    [MethodImpl(AggressiveInlining.Flag)]
    public Promise(Exception e) {
      this.State = Failed;
      this.Readers = new Fail<T>(e); // We assume failures are infrequent.
    }

    internal override void DoJob(ref Worker wr, Cont<T> aK) {
    Spin:
      var state = this.State;
      if (state < Running) goto Completed;
      if (state > Running) goto Spin;
      if (state != Interlocked.CompareExchange(ref this.State, Locked, state)) goto Spin;

      WaitQueue.AddTaker(ref this.Readers, aK);
      this.State = Running;
      return;

    Completed:
      if (state == Completed)
        Cont.Do(aK, ref wr, this.Value);
      else
        Handler.DoHandle(aK, ref wr, (this.Readers as Fail<T>).exn);
    }

    internal override void TryAlt(ref Worker wr, int i, Pick pkSelf, Cont<T> aK, Else<T> aE) {
    Spin:
      var state = this.State;
      if (state < Running) goto Completed;
      if (state > Running) goto Spin;
      if (state != Interlocked.CompareExchange(ref this.State, Locked, state)) goto Spin;

      WaitQueue.AddTaker(ref this.Readers, i, pkSelf, aK);
      this.State = Running;
      aE.TryElse(ref wr, i + 1, pkSelf, aK);
      return;

    Completed:
      var stSelf = Pick.TryPick(pkSelf);
      if (stSelf > 0) goto AlreadyPicked;
      if (stSelf < 0) goto Completed;

      Pick.SetNacks(ref wr, i, pkSelf);

      if (state == Completed)
        Cont.Do(aK, ref wr, this.Value);
      else
        Handler.DoHandle(aK, ref wr, (this.Readers as Fail<T>).exn);
    AlreadyPicked:
      return;
    }

    internal sealed class PrCont : Cont<T> {
      private readonly Promise<T> pr;

      [MethodImpl(AggressiveInlining.Flag)]
      internal PrCont(Promise<T> pr) {
        this.pr = pr;
      }

      [MethodImpl(AggressiveInlining.Flag)]
      internal void Do(ref Worker wr, T v) {
        var pr = this.pr;
        pr.Value = v;
      Spin:
        var state = pr.State;
        if (state > Running) goto Spin;
        if (Running != Interlocked.CompareExchange(ref pr.State, Completed, Running)) goto Spin;

        var readers = pr.Readers;
        if (null == readers)
          return;
        pr.Readers = null;
        Work cursor = readers;
      TryReader:
        var reader = cursor as Cont<T>;
        cursor = cursor.Next;
        int me = 0;
        var pk = reader.GetPick(ref me);
        if (null == pk) goto GotReader;

      TryPick:
        var st = Pick.TryPick(pk);
        if (st > 0) goto TryNextReader;
        if (st < 0) goto TryPick;

        Pick.SetNacks(ref wr, me, pk);

      GotReader:
        reader.Value = v;
        Worker.Push(ref wr, reader);

      TryNextReader:
        if (cursor != readers) goto TryReader;
      }

      internal override void DoWork(ref Worker wr) {
        Do(ref wr, this.Value);
      }

      internal override void DoCont(ref Worker wr, T v) {
        Do(ref wr, v);
      }

      internal override void DoHandle(ref Worker wr, Exception e) {
        var pr = this.pr;
      Spin:
        var state = pr.State;
        if (state > Running) goto Spin;
        if (Running != Interlocked.CompareExchange(ref pr.State, Locked, Running)) goto Spin;

        var readers = pr.Readers;
        pr.Readers = new Fail<T>(e);
        pr.State = Failed;

        if (null == readers)
          return;
        Work cursor = readers;
      TryReader:
        var reader = cursor as Cont<T>;
        cursor = cursor.Next;
        int me = 0;
        var pk = reader.GetPick(ref me);
        if (null == pk) goto GotReader;

      TryPick:
        var st = Pick.TryPick(pk);
        if (st > 0) goto TryNextReader;
        if (st < 0) goto TryPick;

        Pick.SetNacks(ref wr, me, pk);

      GotReader:
        Worker.PushNew(ref wr, new FailWork(e, reader));

      TryNextReader:
        if (cursor != readers) goto TryReader;
      }
    }
  }
}