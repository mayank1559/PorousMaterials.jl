"""
	V = lennard_jones_potential_energy(r_squared::Float64, σ_squared::Float64, ϵ::Float64) # units: Kelvin

Calculate the lennard jones potential energy given a radius r between two molecules.
σ and ϵ are specific to interaction between two elements.
returns potential energy in units Kelvin.
# Arguments
- `r_squared::Float64`: distance between two (pseudo)atoms in question squared (Angstrom^2)
- `σ_squared::Float64`: sigma parameter in Lennard Jones potential squared (units: Angstrom^2)
- `ϵ::Float64`: epsilon parameter in Lennard Jones potential (units: Kelvin)
"""
function lennard_jones(r_squared::Float64, σ_squared::Float64, ϵ::Float64)
	ratio = (σ_squared / r_squared) ^ 3
	return 4 * ϵ * (ratio ^ 2 - ratio)
end

"""
    V = vdw_energy(framework::Framework, molecule::Molecule, ljforcefield::LennardJonesForceField, repfactors::Array{Int64})

Calculates the van der Waals energy for a molecule locates at a specific position in a MOF 
supercell. Uses the nearest image convention to find the closest replicate of a specific atom
# Arguments
- `framework::Framework`: Crystal structure
- `molecule::Molecule`: adsorbate (includes position/orientation)
- `ljforcefield::LennardJonesForceField`: Lennard Jones force field
- `repfactors::Tuple{Int, Int, Int}`: replication factors of the home unit cell to build 
the supercell, which is the simulation box, such that the nearest image convention can be 
applied in this function.
"""
function vdw_energy(framework::Framework, molecule::Molecule, 
                    ljforcefield::LennardJonesForceField, repfactors::Tuple{Int, Int, Int})
	energy = 0.0
    # loop over replications of the home unit cell to build the supercell (simulation box)
	for nA = 0:repfactors[1]-1, nB = 0:repfactors[2]-1, nC = 0:repfactors[3]-1
        # loop over atoms of the molecule/adsorbate
        # TODO: think about whether i or k loop should go first for speed. might not matter.
		for i = 1:molecule.n_atoms 
            # loop over framework atoms in the home unit cell
			for k = 1:framework.n_atoms
				# Nearest image convention. 
                #  If the interaction between the probe molecule and atom k is being looked 
                #  at, we'll only look at the interaction between the probe molecule and 
                #  the closest replication of atom k. This is done with fractional 
                #  coordinates for simplication and transformation to cartesian is done 
                #  later.
				repvec = [nA, nB, nC]
                
                # distance in fractional coordinate space
				dxf = (framework.box.c_to_f * molecule.pos) - (framework.xf[:, k ] + repvec)
				dx = zeros(3)

				for j = 3:-1:1
					if abs(dxf[j]) > repfactors[j] / 2
						repvec[j] += sign(dxf[j]) * repfactors[j]
						dx[j] = framework.box.f_to_c[j,j:end]' * repvec[j:end]	
					end
				end
                
                # Cartesian coordinates of nearest image framework atom.
				x_k = framework.xf[:, k] + dx
                
				r_squared = sum((molecule.pos[:,i] - x_k).^2)
				σ_squared = ljforcefield.sigmas_squared[framework.atoms[k]][molecule.atoms[i]]
				ϵ = ljforcefield.epsilons[framework.atoms[k]][molecule.atoms[i]]
                
				if r_squared < ljforcefield.cutoffradius_squared
                    # add pairwise contribution to potential energy
				    energy += lennard_jones(r_squared, σ_squared, ϵ)
				end
			end
		end
	end
	return energy
end # vdw_energy end
