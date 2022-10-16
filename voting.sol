// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

contract Voting is Ownable{
    //-------------------------------------------------------------------------
    //Remarques                         Auteur : Régis Rem.
    //-------------------------------------------------------------------------
    //
    // + les fonctions sont nommées pour être dans l'ordre du cycle dans remix
    // + l'index des propositions commence à 1 pour l'affichage
    //
    // * l'adminisrateur n'est pas forcément dans whiteListe.
    // * les cycles de votes sont des sessions : 
    //    -> les résultats sont sauvegarder par session
    //    -> les propositions sont gardées et servent à toutes les sessions
    //
    //-------------------------------------------------------------------------

    //-------------------------------------------------------------------------
    //Variables
    //-------------------------------------------------------------------------

    //---------Etapes du cycle de vote
    enum WorkflowStatus {               
        RegisteringVoters,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }
    WorkflowStatus public status = WorkflowStatus.VotesTallied;

    //---------Cycle d'initialisation de la session
    uint                       private Session;

    //---------Cycle d'enregistrement des participants
    uint                       private PreExistants;
    uint                       private Participants;

    //---------Cycle d'enregistrement des propositions
    struct Proposal {
        string description;
        uint   voteCount;
    }
    Proposal[]                 private Proposals;
    mapping(uint => address)   private ProposalIdByAdr;     //toutes n'ont pas fait de propositions...

    //---------Cycle d'enregistrement des votes
    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint votedProposalId;
    }
    uint                       private AVoter;
    mapping(address => Voter)  public  WhiteList;           //toutes doivent voter une fois...
    
    //---------Cycle du dépouillement des votes
    uint                       private VotesMaxi;
    mapping(uint => uint[])    private winningProposalId;   //chaque session, ces winners...

    // structure pour afficher les propositions
    struct ProposalPrnt {
        address addr;
        uint id;
        Proposal idea;
    }

    //-------------------------------------------------------------------------
    //Evénements
    //-------------------------------------------------------------------------
    event VoterRegistered(address voterAddress); 
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted(address voter, uint proposalId);

    event NewSession(uint);
    event AllVoted(string);
    event ProposalsPrnt(string, ProposalPrnt[]);


    //-------------------------------------------------------------------------
    //Modifiers
    //-------------------------------------------------------------------------
    modifier statuer(WorkflowStatus _etape) {
        require(status == _etape, unicode"Cette étape n'est pas en cours...");
        _;
    }

    modifier valider(uint _input) {
        require(_input > 0 , unicode"Aucune entrée...");
        _;
    }

    modifier groupe() {
        require(WhiteList[msg.sender].isRegistered == true, unicode"Vous n'avez pas été enregistré pour ce vote...");
        _;
    }


    //-------------------------------------------------------------------------
    //Constructor
    //-------------------------------------------------------------------------
    constructor() {
        LoadPreExistants();
    }

    //-------------------------------------------------------------------------
    //Fonctions de la gestion du cycle
    //-------------------------------------------------------------------------
    function LoadPreExistants() private {
        // chargement de la liste des participants pré-enregistrés.
        status = WorkflowStatus.RegisteringVoters;
        Participants = 0;
        A0_Nouveau_Particpant(0x5B38Da6a701c568545dCfcB03FcB875f56beddC4);
        A0_Nouveau_Particpant(0xAb8483F64d9C6d1EcF9b849Ae677dD3315835cb2);
        PreExistants = 2;
        status = WorkflowStatus.VotesTallied;
    }

    function NewStatus(WorkflowStatus _newStatus) private returns(WorkflowStatus) {
        WorkflowStatus previousStatus = WorkflowStatus(uint(_newStatus) - 1);
        emit WorkflowStatusChange(previousStatus, _newStatus);
        return _newStatus;
    }

    //
    //--------Cycle d'enregistrement des nouveaux participants-----------------
    //
    function A0_Init_Session() public onlyOwner statuer(WorkflowStatus.VotesTallied) { 
        // permet de faire une ré-initialisation aprés un cycle complet.
        if(winningProposalId[Session].length > 0){
            for(uint i = 1 ; i <= Proposals.length; i++) {
               WhiteList[ProposalIdByAdr[i]].isRegistered = false;
               WhiteList[ProposalIdByAdr[i]].hasVoted = false;
               Proposals[i-1].voteCount = 0;
            }
            LoadPreExistants();
        }
 
        // initialisation de la session.
        Session = block.timestamp;
        AVoter = 0;
        // averti qu'une nouvelle session commence en envoyant le moment de sa création.
        emit NewSession(Session);

        status = WorkflowStatus.RegisteringVoters;
    }

    function A0_Nouveau_Particpant(address _addr) public onlyOwner statuer(WorkflowStatus.RegisteringVoters) valider(uint256(uint160(_addr))) {
        require(WhiteList[_addr].isRegistered == false, unicode"Ce votant est déjà enregistré...");

        // enregistrement du nouveau participant
        WhiteList[_addr].isRegistered = true;
        // un participant de plus
        Participants += 1;
        // averti qu'un nouveau participant a été enregistré en envoyant son Adr.
        emit VoterRegistered(_addr);
    }

    //
    //--------Cycle d'enregistrement des propositions--------------------------
    //
    function A1_Init_Propositions() public  onlyOwner statuer(WorkflowStatus.RegisteringVoters) {
        status = NewStatus(WorkflowStatus.ProposalsRegistrationStarted);
    }

    function A1_Nouvelle_Proposition(string memory _proposition) public groupe statuer(WorkflowStatus.ProposalsRegistrationStarted) valider(bytes(_proposition).length) { 
        // y-a-t-il une proposition identique ?
        for(uint i = 1; i <= Proposals.length ; i++) {
            if(keccak256(bytes(Proposals[i-1].description)) == keccak256(bytes(_proposition)) ) {
                revert(unicode"Proposition déjà enregistrée...");
            }
        }

        // enregistrement de la nouvelle proposition.
        Proposals.push(Proposal(_proposition, 0));
        // enregistrement l'auteur de la nouvelle proposition.
        ProposalIdByAdr[Proposals.length] = msg.sender;
        // averti qu'une nouvelle proposition a été enregistrée en envoyant son Id.
        emit ProposalRegistered(Proposals.length);
    }
    
    //
    //--------Cycle d'enregistrement des votes---------------------------------
    //
    function A2_Init_Votes() public onlyOwner statuer(WorkflowStatus.ProposalsRegistrationStarted){
        status = NewStatus(WorkflowStatus.VotingSessionStarted);
    }

    function A3_Nouveau_Vote(uint _propositionId) public groupe statuer(WorkflowStatus.VotingSessionStarted) valider(_propositionId) {        
        require(_propositionId <= Proposals.length, "Proposition inconnue...");
        require(WhiteList[msg.sender].hasVoted == false, unicode"Vous avez déjà vote...");

        // un participant de plus a voté.
        AVoter += 1;
        // comptabilisation du vote.
        Proposals[_propositionId - 1].voteCount += 1;
        // enregistrement du nouveau vote.
        WhiteList[msg.sender].hasVoted = true;
        WhiteList[msg.sender].votedProposalId = _propositionId;

        // averti qu'un participant a voté en envoyant son Adr et l'Id de la propositions choisie.'
        emit Voted(msg.sender, _propositionId);
        //averti que tous les participants ont fini de voter.
        if(Participants == AVoter) { emit AllVoted(unicode"Tous les participants ont voté..."); }
    }

    //
    //--------Cycle du dépouillement des votes---------------------------------
    //
    function A4_Depouillement_Votes() public onlyOwner statuer(WorkflowStatus.VotingSessionStarted) {
        require(Participants == AVoter, "Tous les participants n'ont pas fini de voter...");

        status = NewStatus(WorkflowStatus.VotingSessionEnded);

        // détermine le nombre de voix maximum atteint pour le(s) vote(s) gagnant(s).
        for (uint i = 0; i < Proposals.length; i++) {
            if (Proposals[i].voteCount > VotesMaxi) { VotesMaxi = Proposals[i].voteCount; }
        }
        // enregistre les propositions gagnantes.
        for (uint i = 0; i < Proposals.length; i++) {
            if (Proposals[i].voteCount == VotesMaxi) { winningProposalId[Session].push(i); }
        }

        status = NewStatus(WorkflowStatus.VotesTallied);
    }

    //-------------------------------------------------------------------------
    //Fonctions d'affichage
    //-------------------------------------------------------------------------
    function sortProposals(bool _winners, uint _counter , string memory message) private {
        uint j;
        ProposalPrnt[] memory ProposalsLst = new ProposalPrnt[](_counter); 

        for (uint i = 0; i < _counter; i++) {
            j = i;
            if (_winners == true) { j = winningProposalId[Session][i]; }
            ProposalsLst[i] = ProposalPrnt(ProposalIdByAdr[j + 1] , j + 1 , Proposal(Proposals[j].description, Proposals[j].voteCount));
        }
        // affiche la liste des propositions résultantes du choix.
        emit ProposalsPrnt(message, ProposalsLst);
    }

    //
    //--------Liste de toutes les propositions gagnantes-----------------------
    //
    function A5_getWinner () public statuer(WorkflowStatus.VotesTallied) {
        sortProposals(true, winningProposalId[Session].length , "winners proposals");
    } 

    //
    //--------Liste de toutes les propositions---------------------------------------
    //
    function AB_getProposals() public valider(Proposals.length) {
        sortProposals(false, Proposals.length , "all proposals");
    }
}
