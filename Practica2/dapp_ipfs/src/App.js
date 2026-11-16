import React, { useEffect, useState } from "react";
import './App.css';
import { create } from 'kubo-rpc-client'
import { ethers } from "ethers"
import { Buffer } from "buffer"
import logo from "./ethereumLogo.png"
import { addresses, abis } from "./contracts"

const defaultProvider = new ethers.providers.Web3Provider(window.ethereum);

const ipfsContract = new ethers.Contract(
  addresses.ipfs,
  abis.ipfs,
  defaultProvider
);

// Escribe el CID del acta en el contrato (requiere firma de MetaMask)
async function registrarActa(id, cid) {
  const c = ipfsContract.connect(defaultProvider.getSigner());
  const tx = await c.registrarActa(id, cid);
  await tx.wait();
}

function App() {
  const [idPartida, setIdPartida] = useState("");
  const [file, setFile] = useState(null);
  const [acta, setActa] = useState(null);
  const [info, setInfo] = useState("");

  useEffect(() => {
    window.ethereum.request({ method: "eth_requestAccounts" });
  }, []);

  const handleSubmit = async (e) => {
    e.preventDefault();
    try {
      if (idPartida === "") { setInfo("Escribe el id de la partida"); return; }
      if (!file) { setInfo("Selecciona un archivo"); return; }

      setInfo("Subiendo a IPFS...");
      const client = await create('/ip4/127.0.0.1/tcp/5001');
      const result = await client.add(file);
      await client.files.cp(`/ipfs/${result.cid}`, `/${result.cid}`);

      setInfo("Registrando el CID en Ethereum (confirma en MetaMask)...");
      await registrarActa(idPartida, result.cid.toString());
      setInfo(`Acta registrada. CID: ${result.cid.toString()}`);
    } catch (error) {
      console.log(error.message);
      setInfo("Error: " + error.message);
    }
  };

  const consultarActa = async () => {
    try {
      if (idPartida === "") { setInfo("Escribe el id de la partida"); return; }
      const r = await ipfsContract.actas(idPartida);
      if (r.autor === ethers.constants.AddressZero) {
        setInfo("No hay acta registrada para esa partida");
        setActa(null);
        return;
      }
      const url = `http://127.0.0.1:8080/ipfs/${r.cid}`;
      const datos = await (await fetch(url)).json();
      setActa(datos);
      setInfo(`Autor: ${r.autor} | CID: ${r.cid}`);
    } catch (error) {
      console.log(error.message);
      setInfo("Error: " + error.message);
    }
  };

  const retrieveFile = (e) => {
    const data = e.target.files[0];
    if (!data) return;
    const reader = new window.FileReader();
    reader.readAsArrayBuffer(data);
    reader.onloadend = () => {
      setFile(Buffer(reader.result));
    };
  };

  return (
    <div className="App">
      <header className="App-header">
        <img src={logo} className="App-logo" alt="logo" />
        <p>Registra o consulta el acta de una partida de bingo.</p>

        <input
          type="number"
          min="0"
          placeholder="ID de la partida"
          value={idPartida}
          onChange={(e) => setIdPartida(e.target.value)}
        />

        <form className="form" onSubmit={handleSubmit}>
          <input type="file" name="data" onChange={retrieveFile} />
          <button type="submit" className="btn">Upload</button>
        </form>

        <button className="btn" onClick={consultarActa}>Consultar acta</button>

        <p style={{ fontSize: "14px", wordBreak: "break-all" }}>{info}</p>
        {acta && (
          <pre style={{ fontSize: "12px", textAlign: "left" }}>
            {JSON.stringify(acta, null, 2)}
          </pre>
        )}
      </header>
    </div>
  );
}

export default App;
